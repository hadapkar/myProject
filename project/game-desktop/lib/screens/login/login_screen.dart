import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:http/http.dart" as http;
import "package:supabase_flutter/supabase_flutter.dart";

import "../../config/app_config.dart";
import "../../services/android_update_gate.dart";
import "../../services/android_update_service.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _loginCheckTimeout = Duration(seconds: 12);
  static const _signInTimeout = Duration(seconds: 20);

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
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
        setState(() => _message = "Password is required");
        return;
      }

      // Block at login page (before Supabase sign-in).
      final check = await _loginCheck(raw);
      final allowed = check["allowed"] == true;
      if (!allowed) {
        final reason = (check["reason"] ?? "blocked").toString();
        final endsAt = (check["endsAt"] ?? "").toString();
        final suffix = endsAt.isNotEmpty ? " (endsAt: $endsAt)" : "";
        setState(() => _message = "Login blocked: $reason$suffix");
        return;
      }

      final email =
          raw.contains("@") ? raw : "${raw.toLowerCase()}@kingmaker.local";
      final response = await Supabase.instance.client.auth
          .signInWithPassword(
            email: email,
            password: _passwordController.text,
          )
          .timeout(_signInTimeout);
      if (!mounted) return;
      if (response.session == null) {
        setState(() => _message = "Sign in failed. Please retry.");
        return;
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
      res = await http
          .get(uri, headers: {"Accept": "application/json"})
          .timeout(_loginCheckTimeout);
    } on TimeoutException {
      throw StateError("Backend is not reachable. Please retry in a minute.");
    } on http.ClientException catch (e) {
      // Retry once through the configured fallback if the network lookup fails.
      if (e.message.contains("Failed host lookup")) {
        final fallbackUri =
            AppConfig.apiUriWithFallback("/public/login-check", queryParameters: query);
        try {
          res = await http
              .get(fallbackUri, headers: {"Accept": "application/json"})
              .timeout(_loginCheckTimeout);
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
    return Scaffold(
      body: SafeArea(
        child: Column(
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
                        const Text(
                          "King Maker",
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
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
                          decoration: const InputDecoration(labelText: "Password"),
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _busy ? null : _signIn,
                          child: Text(_busy ? "Working..." : "Sign in"),
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _message!,
                            style: const TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
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
                "Version ${AndroidUpdateService.currentVersion}",
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
