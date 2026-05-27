import "app_config_runtime.dart";

class AppConfig {
  static String supabaseUrl = const String.fromEnvironment("SUPABASE_URL");
  static String supabaseAnonKey = const String.fromEnvironment("SUPABASE_ANON_KEY");
  static String apiBaseUrl = const String.fromEnvironment("API_BASE_URL");

  static bool get isValid =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && apiBaseUrl.isNotEmpty;

  static Future<void> init() async {
    if (isValid) return;

    final loaded = await AppConfigRuntime.load();
    if (loaded.supabaseUrl.isNotEmpty) supabaseUrl = loaded.supabaseUrl;
    if (loaded.supabaseAnonKey.isNotEmpty) supabaseAnonKey = loaded.supabaseAnonKey;
    if (loaded.apiBaseUrl.isNotEmpty) apiBaseUrl = loaded.apiBaseUrl;
  }
}

