class AppConfig {
  static const supabaseUrl = String.fromEnvironment("SUPABASE_URL");
  static const supabaseAnonKey = String.fromEnvironment("SUPABASE_ANON_KEY");
  static const apiBaseUrl = String.fromEnvironment("API_BASE_URL");

  static bool get isValid =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      apiBaseUrl.isNotEmpty;
}

