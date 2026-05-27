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
              "Missing required configuration.\n\n"
              "Desktop (recommended): create a `config.json` file next to the .exe:\n"
              "{\n"
              "  \"SUPABASE_URL\": \"https://<project>.supabase.co\",\n"
              "  \"SUPABASE_ANON_KEY\": \"<anon>\",\n"
              "  \"API_BASE_URL\": \"https://<render-service>.onrender.com\"\n"
              "}\n\n"
              "Or set Windows environment variables:\n"
              "  SUPABASE_URL / SUPABASE_ANON_KEY / API_BASE_URL\n\n"
              "Dev (Flutter):\n"
              "  flutter run -d windows --dart-define=SUPABASE_URL=... "
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
