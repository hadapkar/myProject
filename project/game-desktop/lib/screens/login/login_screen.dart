import "dart:convert";

import "package:flutter/material.dart";
import "package:http/http.dart" as http;
import "package:supabase_flutter/supabase_flutter.dart";

import "../../config/app_config.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _message;

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
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      setState(() => _message = e.message);
    } on StateError catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>> _loginCheck(String username) async {
    final baseUrl = AppConfig.apiBaseUrl.replaceAll(RegExp(r"\\s+"), "");
    if (baseUrl.isEmpty) {
      throw StateError("Missing API_BASE_URL");
    }
    final uri = Uri.parse("${baseUrl}/public/login-check")
        .replace(queryParameters: {"username": username.trim().toLowerCase()});
    final res = await http.get(uri, headers: {"Accept": "application/json"});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Login check failed (${res.statusCode}). Please retry.");
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw StateError("Login check failed (bad response).");
  }

  @override
  Widget build(BuildContext context) {
    final backend = AppConfig.apiBaseUrl.replaceAll(RegExp(r"\\s+"), "");
    return Scaffold(
      body: Center(
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
                const SizedBox(height: 12),
                Text(
                  "Backend: $backend",
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center,
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
    );
  }
}
