import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../services/update_service.dart";
import "../../services/funtarget_api.dart";

const _funTargetLogo = "assets/app/logo.jpg";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = FunTargetApi();
  bool _isAdmin = false;
  bool _roleLoaded = false;
  bool _subscriptionChecked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRole());
    unawaited(_checkSubscriptionGate());
    if (!kIsWeb) {
      // Background check; UI will show "update available" if needed.
      UpdateService.instance.checkForUpdates();
    }
  }

  Future<void> _loadRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final uid = user?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from("admin_users")
          .select("user_id")
          .eq("user_id", uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _isAdmin = row != null;
        _roleLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _roleLoaded = true);
    }
  }

  Future<void> _checkSubscriptionGate() async {
    if (_subscriptionChecked) return;
    _subscriptionChecked = true;
    try {
      await _api.getMe();
    } on StateError catch (e) {
      final msg = e.message;
      if (!mounted) return;
      if (msg.contains("subscription_inactive") || msg.contains("user_blocked")) {
        final title = msg.contains("user_blocked") ? "Access blocked" : "Subscription inactive";
        final body = msg.contains("user_blocked")
            ? "Your access is blocked or expired. Please contact the admin."
            : "Your subscription is inactive or expired. Please contact the admin.";
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ],
          ),
        );
        await Supabase.instance.client.auth.signOut();
      }
    } catch (_) {
      // Ignore other errors here; the Game screen will show a retryable message.
    }
  }

  Future<void> _openCreateUserDialog() async {
    if (!_isAdmin) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _CreateUserDialog(api: _api),
    );
  }

  void _openUserAccessDashboard() {
    if (!_isAdmin) return;
    context.go("/admin/access");
  }

  Future<void> _openUpdateDialog() async {
    if (kIsWeb) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return ValueListenableBuilder(
          valueListenable: UpdateService.instance.state,
          builder: (context, UpdateState update, _) {
            final available = update.available;
            return AlertDialog(
              title: const Text("Update"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Current: ${UpdateService.currentVersion}"),
                  const SizedBox(height: 8),
                  if (update.checking) const Text("Checking for updates..."),
                  if (update.error != null)
                    Text(update.error!, style: const TextStyle(color: Colors.redAccent)),
                  if (available == null && !update.checking && update.error == null)
                    const Text("No updates available."),
                  if (available != null) Text("Available: ${available.latestTag}"),
                  if (update.installing) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: update.progress01),
                    const SizedBox(height: 8),
                    const Text("Downloading update..."),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: update.installing ? null : () => Navigator.of(context).pop(),
                  child: const Text("Close"),
                ),
                TextButton(
                  onPressed: update.installing
                      ? null
                      : () => UpdateService.instance.checkForUpdates(force: true),
                  child: const Text("Check"),
                ),
                if (available != null)
                  FilledButton(
                    onPressed: update.installing
                        ? null
                        : () async => UpdateService.instance.downloadAndInstall(),
                    child: const Text("Update now"),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? "-";

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        title: const Text("Games"),
        actions: [
          if (_roleLoaded && _isAdmin)
            TextButton(
              onPressed: _openCreateUserDialog,
              child: const Text("Create User"),
            ),
          if (_roleLoaded && _isAdmin)
            TextButton(
              onPressed: _openUserAccessDashboard,
              child: const Text("Subscriptions"),
            ),
          if (!kIsWeb)
            ValueListenableBuilder(
              valueListenable: UpdateService.instance.state,
              builder: (context, UpdateState update, _) {
                final hasUpdate = update.available != null;
                final color = hasUpdate ? Colors.amberAccent : Colors.white70;
                return IconButton(
                  tooltip: hasUpdate ? "Update available" : "Updates",
                  onPressed: _openUpdateDialog,
                  icon: Icon(Icons.system_update_alt, color: color),
                );
              },
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(email, style: const TextStyle(color: Colors.white70)),
            ),
          ),
          TextButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            child: const Text("Sign out"),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 1100
                ? 4
                : width >= 820
                    ? 3
                    : width >= 520
                        ? 2
                        : 1;
            return GridView.count(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.4,
              children: [
                _GameTile(
                  title: "FunTarget",
                  subtitle: "Wheel / Bet game",
                  imageAsset: _funTargetLogo,
                  onTap: () => context.go("/game"),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  final FunTargetApi api;

  const _CreateUserDialog({required this.api});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _role = "MANAGER";
  DateTime? _endDateLocal;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final endsAtIsoUtc = _endDateLocal == null
          ? ""
          : DateTime(
                  _endDateLocal!.year, _endDateLocal!.month, _endDateLocal!.day, 0, 0, 0)
              .toUtc()
              .toIso8601String();
      final res = await widget.api.createUser(
        username: _username.text.trim(),
        password: _password.text,
        role: _role,
        endsAt: endsAtIsoUtc,
      );
      final createdUsername = (res["username"] ?? "").toString();
      final createdEmail = (res["email"] ?? "").toString();
      setState(() => _message = "Created user: $createdUsername ($createdEmail)");
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Create User"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: "Username",
                hintText: "Example: manager01",
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: "Temporary password"),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(_role),
              initialValue: _role,
              decoration: const InputDecoration(labelText: "Role"),
              items: const [
                DropdownMenuItem(value: "MANAGER", child: Text("Manager")),
                DropdownMenuItem(value: "ADMIN", child: Text("Admin")),
              ],
              onChanged: _busy ? null : (v) => setState(() => _role = v ?? "MANAGER"),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: "End date (optional)"),
                    child: Text(
                      _endDateLocal == null
                          ? "-"
                          : "${_endDateLocal!.year.toString().padLeft(4, "0")}-"
                              "${_endDateLocal!.month.toString().padLeft(2, "0")}-"
                              "${_endDateLocal!.day.toString().padLeft(2, "0")}",
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            initialDate: _endDateLocal ?? DateTime.now(),
                          );
                          if (picked == null) return;
                          if (!mounted) return;
                          setState(() => _endDateLocal = picked);
                        },
                  child: const Text("Pick"),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _endDateLocal = null),
                  child: const Text("Clear"),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(
                _message!,
                style: TextStyle(
                  color: _message!.startsWith("Created") ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: Text(_busy ? "Creating..." : "Create"),
        ),
      ],
    );
  }
}

class _GameTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageAsset;
  final VoidCallback onTap;

  const _GameTile({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color.fromRGBO(255, 255, 255, 0.06),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.10)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 96,
                  height: 96,
                  color: const Color.fromRGBO(0, 0, 0, 0.25),
                  child: Image.asset(imageAsset, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(Icons.play_arrow, size: 18, color: Colors.white70),
                        SizedBox(width: 6),
                        Text("Play", style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
