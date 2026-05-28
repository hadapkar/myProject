import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;
import "package:supabase_flutter/supabase_flutter.dart";

import "../config/app_config.dart";
import "funtarget_models.dart";

class FunTargetApi {
  static const Duration _timeout = Duration(seconds: 65);

  final http.Client _client = http.Client();

  Uri _uri(String path) => Uri.parse("${AppConfig.apiBaseUrl}$path");

  Future<String> _accessToken({bool allowRefresh = true}) async {
    final auth = Supabase.instance.client.auth;
    var session = auth.currentSession;
    if (session == null) {
      throw StateError("Not authenticated");
    }

    // If the session is near expiry, try a refresh once.
    if (allowRefresh) {
      final expiresAt = session.expiresAt;
      if (expiresAt != null) {
        final expiry =
            DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true);
        final now = DateTime.now().toUtc();
        if (!expiry.isAfter(now.add(const Duration(seconds: 30)))) {
          final refreshed = await auth.refreshSession();
          session = refreshed.session ?? auth.currentSession;
        }
      }
    }

    final token = session?.accessToken;
    if (token == null || token.isEmpty) throw StateError("Not authenticated");
    return token;
  }

  Future<http.Response> _get(String path) async {
    final token = await _accessToken();
    http.Response res;
    try {
      res = await _client
          .get(
            _uri(path),
            headers: {
              "Authorization": "Bearer $token",
              "Accept": "application/json",
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw StateError("Backend timeout. The server may be waking up; please retry.");
    }

    // If token is stale, refresh session and retry once.
    if (res.statusCode == 401) {
      final retryToken = await _accessToken(allowRefresh: true);
      try {
        return await _client
            .get(
              _uri(path),
              headers: {
                "Authorization": "Bearer $retryToken",
                "Accept": "application/json",
              },
            )
            .timeout(_timeout);
      } on TimeoutException {
        throw StateError("Backend timeout. The server may be waking up; please retry.");
      }
    }
    return res;
  }

  Future<http.Response> _post(String path, Map<String, dynamic> payload) async {
    final token = await _accessToken();
    http.Response res;
    try {
      res = await _client
          .post(
            _uri(path),
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw StateError("Backend timeout. The server may be waking up; please retry.");
    }

    if (res.statusCode == 401) {
      final retryToken = await _accessToken(allowRefresh: true);
      try {
        return await _client
            .post(
              _uri(path),
              headers: {
                "Authorization": "Bearer $retryToken",
                "Content-Type": "application/json",
                "Accept": "application/json",
              },
              body: jsonEncode(payload),
            )
            .timeout(_timeout);
      } on TimeoutException {
        throw StateError("Backend timeout. The server may be waking up; please retry.");
      }
    }
    return res;
  }

  Future<FunTargetState> getState() async {
    final res = await _get("/api/funtarget/state");
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Backend error ${res.statusCode}: ${res.body}");
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return FunTargetState.fromJson(jsonMap);
  }

  Future<FunTargetState> postIntent(Map<String, dynamic> payload) async {
    final res = await _post("/api/funtarget/intent", payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Backend error ${res.statusCode}: ${res.body}");
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return FunTargetState.fromJson(jsonMap);
  }

  Future<Map<String, dynamic>> createUser({
    required String email,
    required String password,
    required String role,
  }) async {
    final res = await _post("/api/admin/users", {
      "email": email,
      "password": password,
      "role": role,
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Backend error ${res.statusCode}: ${res.body}");
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return jsonMap;
  }
}
