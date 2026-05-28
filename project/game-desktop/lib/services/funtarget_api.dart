import "dart:async";
import "dart:convert";
import "dart:math";

import "package:http/http.dart" as http;
import "package:flutter/foundation.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../config/app_config.dart";
import "funtarget_models.dart";
import "../storage/session_store.dart";

class FunTargetApi {
  static const Duration _timeout = Duration(seconds: 65);

  final http.Client _client = http.Client();

  String? _cachedSessionId;
  String? _cachedDeviceId;

  Uri _uri(String path) => Uri.parse("${AppConfig.apiBaseUrl}$path");

  StateError _apiError(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        final err = (decoded["error"] ?? "").toString();
        final msg = (decoded["message"] ?? "").toString();
        if (err == "subscription_inactive") {
          final endsAt = (decoded["subscriptionEndsAt"] ?? "").toString();
          final suffix = endsAt.isNotEmpty ? " (endsAt: $endsAt)" : "";
          return StateError("subscription_inactive: Subscription inactive$suffix");
        }
        if (err == "user_blocked") {
          final endsAt = (decoded["endsAt"] ?? "").toString();
          final suffix = endsAt.isNotEmpty ? " (endsAt: $endsAt)" : "";
          return StateError("user_blocked: User blocked$suffix");
        }
        if (err == "session_conflict") {
          return StateError("session_conflict: Logged in elsewhere");
        }
        if (err == "missing_session") {
          return StateError("missing_session: Session missing");
        }
        if (err.isNotEmpty) {
          return StateError("Backend error ${res.statusCode}: $err${msg.isNotEmpty ? " - $msg" : ""}");
        }
      }
    } catch (_) {
      // Ignore parse errors; fall back to raw body.
    }
    return StateError("Backend error ${res.statusCode}: ${res.body}");
  }

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
    final sessionId = await _ensureSession(token: token);
    http.Response res;
    try {
      res = await _client
          .get(
            _uri(path),
            headers: {
              "Authorization": "Bearer $token",
              "Accept": "application/json",
              "X-Session-Id": sessionId,
              "X-Platform": _platform(),
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw StateError("Backend timeout. The server may be waking up; please retry.");
    }

    // If token is stale, refresh session and retry once.
    if (res.statusCode == 401) {
      final retryToken = await _accessToken(allowRefresh: true);
      final sessionId = await _ensureSession(token: retryToken);
      try {
        return await _client
            .get(
              _uri(path),
              headers: {
                "Authorization": "Bearer $retryToken",
                "Accept": "application/json",
                "X-Session-Id": sessionId,
                "X-Platform": _platform(),
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
    final sessionId = await _ensureSession(token: token);
    http.Response res;
    try {
      res = await _client
          .post(
            _uri(path),
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
              "Accept": "application/json",
              "X-Session-Id": sessionId,
              "X-Platform": _platform(),
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw StateError("Backend timeout. The server may be waking up; please retry.");
    }

    if (res.statusCode == 401) {
      final retryToken = await _accessToken(allowRefresh: true);
      final sessionId = await _ensureSession(token: retryToken);
      try {
        return await _client
            .post(
              _uri(path),
              headers: {
                "Authorization": "Bearer $retryToken",
                "Content-Type": "application/json",
                "Accept": "application/json",
                "X-Session-Id": sessionId,
                "X-Platform": _platform(),
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

  String _platform() {
    if (kIsWeb) return "web";
    return "desktop";
  }

  Future<String> _ensureSession({required String token}) async {
    if (_cachedSessionId != null && _cachedSessionId!.isNotEmpty) {
      return _cachedSessionId!;
    }

    // Load persisted ids.
    _cachedSessionId ??= await SessionStore.loadSessionId();
    _cachedDeviceId ??= await SessionStore.loadDeviceId();

    if (_cachedDeviceId == null || _cachedDeviceId!.isEmpty) {
      _cachedDeviceId = _generateDeviceId();
      await SessionStore.saveDeviceId(_cachedDeviceId!);
    }

    // Always (re)start the session on first API use to avoid stale session ids.
    final res = await _client
        .post(
          _uri("/api/session/start"),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
            "Accept": "application/json",
          },
          body: jsonEncode({
            "platform": _platform(),
            "deviceId": _cachedDeviceId,
          }),
        )
        .timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _apiError(res);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError("Session start failed");
    }
    final sessionId = (decoded["sessionId"] ?? "").toString();
    if (sessionId.isEmpty) throw StateError("Session start failed");
    _cachedSessionId = sessionId;
    await SessionStore.saveSessionId(sessionId);
    return sessionId;
  }

  String _generateDeviceId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes).replaceAll("=", "");
  }

  Future<FunTargetState> getState() async {
    final res = await _get("/api/funtarget/state");
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _apiError(res);
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return FunTargetState.fromJson(jsonMap);
  }

  Future<FunTargetState> postIntent(Map<String, dynamic> payload) async {
    final res = await _post("/api/funtarget/intent", payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _apiError(res);
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return FunTargetState.fromJson(jsonMap);
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _get("/api/me");
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _apiError(res);
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return jsonMap;
  }

  Future<Map<String, dynamic>> createUser({
    required String username,
    required String password,
    required String role,
    String endsAt = "",
  }) async {
    final payload = <String, dynamic>{
      "username": username.trim(),
      "password": password,
      "role": role,
    };
    if (endsAt.trim().isNotEmpty) {
      payload["ends_at"] = endsAt.trim();
    }
    final res = await _post("/api/admin/users", payload);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _apiError(res);
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return jsonMap;
  }
}
