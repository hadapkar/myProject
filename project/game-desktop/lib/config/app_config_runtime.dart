// Runtime configuration loader.
//
// - On Windows/macOS/Linux: supports environment variables and `config.json` next to the executable.
// - On Web: returns empty config (web uses `--dart-define`).

import "app_config_runtime_stub.dart"
    if (dart.library.io) "app_config_runtime_io.dart"
    if (dart.library.html) "app_config_runtime_web.dart";

class RuntimeConfig {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String apiBaseUrl;

  const RuntimeConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.apiBaseUrl,
  });

  static const empty = RuntimeConfig(supabaseUrl: "", supabaseAnonKey: "", apiBaseUrl: "");
}

class AppConfigRuntime {
  static Future<RuntimeConfig> load() => loadRuntimeConfig();
}

