import "package:flutter/material.dart";

class ConfigMissingScreen extends StatelessWidget {
  const ConfigMissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Missing required build configuration.\n\n"
              "Run with:\n"
              "  flutter run -d chrome "
              "--dart-define=SUPABASE_URL=... "
              "--dart-define=SUPABASE_ANON_KEY=... "
              "--dart-define=API_BASE_URL=...\n",
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

