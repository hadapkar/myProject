import "app_config_runtime.dart";

class AppConfig {
  static String _sanitizeUrl(String v) => v.replaceAll(RegExp(r"\\s+"), "");

  // `--dart-define` values (GitHub Actions, CI) sometimes end up with trailing
  // newlines/whitespace when copied/pasted into secrets. Strip all whitespace
  // to avoid invalid hostnames like `backend-api- ia1r.onrender.com`.
  static String supabaseUrl = _sanitizeUrl(const String.fromEnvironment("SUPABASE_URL"));
  static String supabaseAnonKey = const String.fromEnvironment("SUPABASE_ANON_KEY").trim();
  static String apiBaseUrl = _sanitizeUrl(const String.fromEnvironment("API_BASE_URL"));

  static bool get isValid =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && apiBaseUrl.isNotEmpty;

  static Future<void> init() async {
    if (isValid) return;

    final loaded = await AppConfigRuntime.load();
    if (loaded.supabaseUrl.isNotEmpty) supabaseUrl = _sanitizeUrl(loaded.supabaseUrl);
    if (loaded.supabaseAnonKey.isNotEmpty) supabaseAnonKey = loaded.supabaseAnonKey.trim();
    if (loaded.apiBaseUrl.isNotEmpty) apiBaseUrl = _sanitizeUrl(loaded.apiBaseUrl);
  }
}
