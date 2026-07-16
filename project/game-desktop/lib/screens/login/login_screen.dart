import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:http/http.dart" as http;
import "package:supabase_flutter/supabase_flutter.dart";

import "../../config/app_config.dart";
import "../../services/android_update_gate.dart";
import "../../services/android_update_service.dart";
import "../../storage/account_store.dart";
import "../../storage/session_store.dart";
import "../../widgets/profile_avatar.dart";

class LoginScreen extends StatefulWidget {
  final bool addAccount;

  const LoginScreen({super.key, this.addAccount = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _loginCheckTimeout = Duration(seconds: 12);
  static const _signInTimeout = Duration(seconds: 20);

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  List<SavedAccount> _savedAccounts = const [];
  bool _busy = false;
  bool _showPassword = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedAccounts());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(AndroidUpdateGate.maybeShow(context));
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await AccountStore.loadAccounts();
    if (!mounted) return;
    setState(() {
      _savedAccounts = accounts;
      if (!widget.addAccount &&
          _usernameController.text.trim().isEmpty &&
          accounts.isNotEmpty) {
        _usernameController.text = accounts.first.username;
      }
    });
  }

  SavedAccount? _savedAccountFor(String usernameOrEmail) {
    final normalized = usernameOrEmail.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final account in _savedAccounts) {
      final email = account.email.toLowerCase();
      final username = account.username.toLowerCase();
      if (normalized == email || normalized == username || normalized == email.split("@").first) {
        return account;
      }
    }
    return null;
  }

  Future<void> _openAccountMenu() async {
    if (_busy) return;
    await _loadSavedAccounts();
    if (!mounted || _savedAccounts.isEmpty) return;
    final action = await showModalBottomSheet<_LoginAccountAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => _LoginAccountSheet(accounts: _savedAccounts),
    );
    if (action == null || !mounted) return;
    if (action.addAccount) {
      setState(() {
        _message = null;
        _usernameController.clear();
        _passwordController.clear();
      });
      return;
    }
    final account = action.account;
    if (account != null) {
      await _signInWithSavedAccount(account);
    }
  }

  Future<void> _signInWithSavedAccount(SavedAccount account) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await SessionStore.clearSessionId();
      final response = await Supabase.instance.client.auth
          .setSession(account.refreshToken)
          .timeout(_signInTimeout);
      final session = response.session ?? Supabase.instance.client.auth.currentSession;
      if (session == null) throw StateError("Please sign in again");
      await AccountStore.upsertAccount(
        username: account.username,
        email: session.user.email ?? account.email,
        refreshToken: session.refreshToken ?? account.refreshToken,
      );
      await _loadSavedAccounts();
      if (!mounted) return;
      context.go("/home");
    } on TimeoutException {
      setState(() => _message = "Sign in timed out. Check your internet and retry.");
    } catch (_) {
      await AccountStore.removeAccount(account.email);
      await AccountStore.removeAccountByRefreshToken(account.refreshToken);
      if (!mounted) return;
      _usernameController.clear();
      await _loadSavedAccounts();
      if (!mounted) return;
      setState(() => _message = "Please sign in again for this account.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final raw = _usernameController.text.trim();
      if (raw.isEmpty) {
        setState(() => _message = "Username is required");
        return;
      }
      if (_passwordController.text.isEmpty) {
        final saved = _savedAccountFor(raw);
        if (saved != null) {
          await _signInWithSavedAccount(saved);
          return;
        }
        setState(() => _message = "Password is required");
        return;
      }

      final check = await _loginCheck(raw);
      final allowed = check["allowed"] == true;
      if (!allowed) {
        setState(() => _message = "Please contact admin");
        return;
      }

      final resolvedEmail = (check["email"] ?? "").toString().trim();
      final email = resolvedEmail.contains("@")
          ? resolvedEmail.toLowerCase()
          : (raw.contains("@") ? raw.toLowerCase() : "${raw.toLowerCase()}@kingmaker.local");
      final response = await Supabase.instance.client.auth
          .signInWithPassword(
            email: email,
            password: _passwordController.text,
          )
          .timeout(_signInTimeout);
      if (!mounted) return;
      final session = response.session;
      if (session == null) {
        setState(() => _message = "Sign in failed. Please retry.");
        return;
      }

      final savedEmail = session.user.email ?? email;
      final refreshToken = session.refreshToken ?? "";
      if (refreshToken.isNotEmpty) {
        await AccountStore.upsertAccount(
          username: raw.contains("@") ? savedEmail.split("@").first : raw.toLowerCase(),
          email: savedEmail,
          refreshToken: refreshToken,
        );
        await _loadSavedAccounts();
      }
      context.go("/home");
    } on AuthException catch (e) {
      setState(() => _message = e.message);
    } on TimeoutException {
      setState(() => _message = "Sign in timed out. Check your internet and retry.");
    } on StateError catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>> _loginCheck(String username) async {
    if (AppConfig.apiBaseUrl.isEmpty) {
      throw StateError("Missing API_BASE_URL");
    }

    final query = {"username": username.trim().toLowerCase()};
    final uri = AppConfig.apiUri("/public/login-check", queryParameters: query);
    http.Response res;
    try {
      res = await http.get(uri, headers: {"Accept": "application/json"}).timeout(_loginCheckTimeout);
    } on TimeoutException {
      throw StateError("Backend is not reachable. Please retry in a minute.");
    } on http.ClientException catch (e) {
      if (e.message.contains("Failed host lookup")) {
        final fallbackUri = AppConfig.apiUriWithFallback("/public/login-check", queryParameters: query);
        try {
          res = await http.get(fallbackUri, headers: {"Accept": "application/json"}).timeout(_loginCheckTimeout);
        } on TimeoutException {
          throw StateError("Backend is not reachable. Please retry in a minute.");
        } on http.ClientException {
          throw StateError("Backend is not reachable. Please retry in a minute.");
        }
      } else {
        throw StateError("Backend is not reachable. Please retry in a minute.");
      }
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Login check failed (${res.statusCode}). Please retry.");
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw StateError("Login check failed (bad response).");
  }

  @override
  Widget build(BuildContext context) {
    final showProfile = _savedAccounts.isNotEmpty;
    final profileAccount = showProfile ? _savedAccounts.first : null;
    final initials = profileAccount == null ? "" : _initialsFor(profileAccount.username);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.addAccount ? "Add Account" : "King Maker",
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _usernameController,
                              decoration: const InputDecoration(labelText: "Username"),
                              keyboardType: TextInputType.text,
                              autofillHints: const [AutofillHints.username],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: "Password",
                                suffixIcon: IconButton(
                                  tooltip: _showPassword ? "Hide password" : "Show password",
                                  onPressed: () => setState(() => _showPassword = !_showPassword),
                                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                                ),
                              ),
                              obscureText: !_showPassword,
                              autofillHints: const [AutofillHints.password],
                            ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _busy ? null : _signIn,
                              child: Text(_busy ? "Working..." : "Sign in"),
                            ),
                            if (_message != null) ...[
                              const SizedBox(height: 12),
                              _LoginMessageBanner(
                                message: _message!,
                                onRetry: _busy || !_canRetryMessage(_message!) ? null : _signIn,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Version ${AndroidUpdateService.currentDisplayVersion}",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            if (showProfile)
              Positioned(
                top: 8,
                left: 12,
                child: _LoginProfileButton(
                  initials: initials,
                  colorSeed: profileAccount?.email ?? initials,
                  onPressed: _openAccountMenu,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

bool _canRetryMessage(String message) {
  return message.contains("Backend") ||
      message.contains("timed out") ||
      message.contains("retry");
}

class _LoginMessageBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _LoginMessageBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.left,
            ),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text("Retry")),
        ],
      ),
    );
  }
}
String _initialsFor(String value) {
  final cleaned = value.trim();
  if (cleaned.isEmpty || cleaned == "-") return "U";
  final parts = cleaned
      .split(RegExp(r"[^A-Za-z0-9]+"))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return cleaned.substring(0, 1).toUpperCase();
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

class _LoginProfileButton extends StatelessWidget {
  final String initials;
  final String colorSeed;
  final VoidCallback onPressed;

  const _LoginProfileButton({
    required this.initials,
    required this.colorSeed,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: ProfileAvatar(initials: initials, seed: colorSeed),
    );
  }
}

class _LoginAccountAction {
  final SavedAccount? account;
  final bool addAccount;

  const _LoginAccountAction.switchTo(this.account) : addAccount = false;
  const _LoginAccountAction.add() : account = null, addAccount = true;
}

class _LoginAccountSheet extends StatelessWidget {
  final List<SavedAccount> accounts;

  const _LoginAccountSheet({required this.accounts});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final account in accounts)
              ListTile(
                leading: ProfileAvatar(initials: _initialsFor(account.username), seed: account.email),
                title: Text(account.username, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).pop(_LoginAccountAction.switchTo(account)),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text("Login to new account"),
              onTap: () => Navigator.of(context).pop(const _LoginAccountAction.add()),
            ),
          ],
        ),
      ),
    );
  }
}
