import "dart:convert";
import "dart:io";

import "app_config_runtime.dart";

Future<RuntimeConfig> loadRuntimeConfig() async {
  // 1) Environment variables (desktop-friendly; not available on web).
  final env = Platform.environment;
  final envUrl = (env["SUPABASE_URL"] ?? "").trim();
  final envAnon = (env["SUPABASE_ANON_KEY"] ?? "").trim();
  final envApi = (env["API_BASE_URL"] ?? "").trim();

  // 2) config.json next to the executable (portable zip distribution).
  RuntimeConfig fileConfig = RuntimeConfig.empty;
  try {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final configFile = File("${exeDir.path}${Platform.pathSeparator}config.json");
    if (await configFile.exists()) {
      final raw = await configFile.readAsString();
      final json = jsonDecode(raw);
      if (json is Map) {
        String pick(String key) {
          final v = json[key] ?? json[key.toLowerCase()] ?? json[key.toUpperCase()];
          return v == null ? "" : v.toString().trim();
        }

        fileConfig = RuntimeConfig(
          supabaseUrl: pick("SUPABASE_URL"),
          supabaseAnonKey: pick("SUPABASE_ANON_KEY"),
          apiBaseUrl: pick("API_BASE_URL"),
        );
      }
    }
  } catch (_) {
    // ignore
  }

  String firstNonEmpty(String a, String b) => a.isNotEmpty ? a : b;

  return RuntimeConfig(
    supabaseUrl: firstNonEmpty(envUrl, fileConfig.supabaseUrl),
    supabaseAnonKey: firstNonEmpty(envAnon, fileConfig.supabaseAnonKey),
    apiBaseUrl: firstNonEmpty(envApi, fileConfig.apiBaseUrl),
  );
}

