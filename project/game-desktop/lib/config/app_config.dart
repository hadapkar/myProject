import "app_config_runtime.dart";

class AppConfig {
  static String _sanitizeUrl(String v) => v.replaceAll(RegExp(r"\\s+"), "");
  static const String defaultApiBaseUrl = "https://backend-api-ia1r.onrender.com";
  static const String fallbackApiBaseUrl = "https://gcp-us-west1-1.origin.onrender.com";

  static String _normalizeBaseUrl(String v, {required String fallback}) {
    final sanitized = _sanitizeUrl(v).trim();
    if (sanitized.isEmpty) return fallback;
    final uri = Uri.tryParse(sanitized);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return fallback;
    // Ensure no trailing slash to keep URI joining predictable.
    final noTrailingSlash = sanitized.endsWith("/") ? sanitized.substring(0, sanitized.length - 1) : sanitized;
    return noTrailingSlash;
  }

  static Uri apiUri(String path, {Map<String, String>? queryParameters}) {
    final base = Uri.parse(_normalizeBaseUrl(apiBaseUrl, fallback: defaultApiBaseUrl));
    final normalizedPath = path.startsWith("/") ? path : "/$path";
    return base.replace(
      path: normalizedPath,
      queryParameters: queryParameters,
    );
  }

  static Uri apiUriWithFallback(String path, {Map<String, String>? queryParameters}) {
    final base = Uri.parse(_normalizeBaseUrl(fallbackApiBaseUrl, fallback: defaultApiBaseUrl));
    final normalizedPath = path.startsWith("/") ? path : "/$path";
    return base.replace(
      path: normalizedPath,
      queryParameters: queryParameters,
    );
  }

  // `--dart-define` values (GitHub Actions, CI) sometimes end up with trailing
  // newlines/whitespace when copied/pasted into secrets. Strip all whitespace
  // to avoid invalid hostnames like `backend-api- ia1r.onrender.com`.
  static String supabaseUrl = _sanitizeUrl(const String.fromEnvironment("SUPABASE_URL"));
  static String supabaseAnonKey = const String.fromEnvironment("SUPABASE_ANON_KEY").trim();
  static String apiBaseUrl = _normalizeBaseUrl(
    const String.fromEnvironment("API_BASE_URL"),
    fallback: defaultApiBaseUrl,
  );

  static bool get isValid =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && apiBaseUrl.isNotEmpty;

  static Future<void> init() async {
    if (isValid) return;

    final loaded = await AppConfigRuntime.load();
    if (loaded.supabaseUrl.isNotEmpty) supabaseUrl = _sanitizeUrl(loaded.supabaseUrl);
    if (loaded.supabaseAnonKey.isNotEmpty) supabaseAnonKey = loaded.supabaseAnonKey.trim();
    // Always normalize (and fall back) to keep mobile builds working even if
    // secrets/env/config are mis-entered with whitespace/newlines.
    apiBaseUrl = _normalizeBaseUrl(
      loaded.apiBaseUrl.isNotEmpty ? loaded.apiBaseUrl : apiBaseUrl,
      fallback: defaultApiBaseUrl,
    );
  }
}
