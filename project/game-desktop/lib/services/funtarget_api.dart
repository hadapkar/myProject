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
  static const Duration _timeout = Duration(seconds: 25);
  static const Duration _meCacheTtl = Duration(seconds: 20);
  static String? _cachedMeUserId;
  static DateTime? _cachedMeAt;
  static Map<String, dynamic>? _cachedMe;

  final http.Client _client = http.Client();

  String? _cachedSessionId;
  String? _cachedDeviceId;

  void clearSessionCache() {
    _cachedSessionId = null;
    clearUserCache();
  }

  static void clearUserCache() {
    _cachedMeUserId = null;
    _cachedMeAt = null;
    _cachedMe = null;
  }

  bool _isHostLookupError(Object e) =>
      e is http.ClientException && e.message.contains("Failed host lookup");

  StateError _networkError(http.ClientException e) {
    if (kIsWeb && e.message.contains("XMLHttpRequest error")) {
      return StateError(
        "Backend request blocked. Check CORS_ALLOWED_ORIGINS and allowed headers.",
      );
    }
    return StateError("Backend is not responding. Please retry.");
  }

  Future<http.Response> _getUri(Uri uri, Map<String, String> headers) =>
      _client.get(uri, headers: headers).timeout(_timeout);

  Future<http.Response> _postUri(Uri uri, Map<String, String> headers, Object body) =>
      _client.post(uri, headers: headers, body: body).timeout(_timeout);

  Future<http.Response> _patchUri(Uri uri, Map<String, String> headers, Object body) =>
      _client.patch(uri, headers: headers, body: body).timeout(_timeout);

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

  Future<http.Response> _get(String path, {Map<String, String>? queryParameters}) async {
    final token = await _accessToken();
    final sessionId = await _ensureSession(token: token);
    http.Response res;
    try {
      final headers = {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
        "X-Session-Id": sessionId,
        "X-Platform": _platform(),
      };
      res = await _getUri(AppConfig.apiUri(path, queryParameters: queryParameters), headers);
    } on http.ClientException catch (e) {
      if (_isHostLookupError(e)) {
        final headers = {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
          "X-Session-Id": sessionId,
          "X-Platform": _platform(),
        };
        res = await _getUri(AppConfig.apiUriWithFallback(path, queryParameters: queryParameters), headers);
      } else {
        throw _networkError(e);
      }
    } on TimeoutException {
      throw StateError("Backend is not responding. Please retry.");
    }

    // If token is stale, refresh session and retry once.
    if (res.statusCode == 401) {
      final retryToken = await _accessToken(allowRefresh: true);
      final sessionId = await _ensureSession(token: retryToken);
      try {
        final headers = {
          "Authorization": "Bearer $retryToken",
          "Accept": "application/json",
          "X-Session-Id": sessionId,
          "X-Platform": _platform(),
        };
        return await _getUri(AppConfig.apiUri(path, queryParameters: queryParameters), headers);
      } on TimeoutException {
        throw StateError("Backend is not responding. Please retry.");
      }
    }
    return res;
  }

  Future<http.Response> _post(String path, Map<String, dynamic> payload) async {
    final token = await _accessToken();
    final sessionId = await _ensureSession(token: token);
    http.Response res;
    try {
      final headers = {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Session-Id": sessionId,
        "X-Platform": _platform(),
      };
      final body = jsonEncode(payload);
      res = await _postUri(AppConfig.apiUri(path), headers, body);
    } on http.ClientException catch (e) {
      if (_isHostLookupError(e)) {
        final headers = {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Session-Id": sessionId,
          "X-Platform": _platform(),
        };
        final body = jsonEncode(payload);
        res = await _postUri(AppConfig.apiUriWithFallback(path), headers, body);
      } else {
        throw _networkError(e);
      }
    } on TimeoutException {
      throw StateError("Backend is not responding. Please retry.");
    }

    if (res.statusCode == 401) {
      final retryToken = await _accessToken(allowRefresh: true);
      final sessionId = await _ensureSession(token: retryToken);
      try {
        final headers = {
          "Authorization": "Bearer $retryToken",
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Session-Id": sessionId,
          "X-Platform": _platform(),
        };
        final body = jsonEncode(payload);
        return await _postUri(AppConfig.apiUri(path), headers, body);
      } on TimeoutException {
        throw StateError("Backend is not responding. Please retry.");
      }
    }
    return res;
  }

  Future<http.Response> _patch(String path, Map<String, dynamic> payload) async {
    final token = await _accessToken();
    final sessionId = await _ensureSession(token: token);
    http.Response res;
    try {
      final headers = {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Session-Id": sessionId,
        "X-Platform": _platform(),
      };
      final body = jsonEncode(payload);
      res = await _patchUri(AppConfig.apiUri(path), headers, body);
    } on http.ClientException catch (e) {
      if (_isHostLookupError(e)) {
        final headers = {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Session-Id": sessionId,
          "X-Platform": _platform(),
        };
        final body = jsonEncode(payload);
        res = await _patchUri(AppConfig.apiUriWithFallback(path), headers, body);
      } else {
        throw _networkError(e);
      }
    } on TimeoutException {
      throw StateError("Backend is not responding. Please retry.");
    }

    if (res.statusCode == 401) {
      final retryToken = await _accessToken(allowRefresh: true);
      final sessionId = await _ensureSession(token: retryToken);
      try {
        final headers = {
          "Authorization": "Bearer $retryToken",
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Session-Id": sessionId,
          "X-Platform": _platform(),
        };
        final body = jsonEncode(payload);
        return await _patchUri(AppConfig.apiUri(path), headers, body);
      } on TimeoutException {
        throw StateError("Backend is not responding. Please retry.");
      }
    }

    return res;
  }

  String _platform() {
    if (kIsWeb) return "web";
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return "mobile";
      default:
        return "desktop";
    }
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
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
      "Accept": "application/json",
    };
    final body = jsonEncode({
      "platform": _platform(),
      "deviceId": _cachedDeviceId,
    });

    http.Response res;
    try {
      res = await _postUri(AppConfig.apiUri("/api/session/start"), headers, body);
    } on http.ClientException catch (e) {
      if (_isHostLookupError(e)) {
        res = await _postUri(
          AppConfig.apiUriWithFallback("/api/session/start"),
          headers,
          body,
        );
      } else {
        throw _networkError(e);
      }
    }

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


  Future<void> endSession() async {
    try {
      final token = await _accessToken(allowRefresh: false);
      final headers = {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      };
      final body = jsonEncode({"platform": _platform()});
      try {
        await _postUri(AppConfig.apiUri("/api/session/end"), headers, body);
      } on http.ClientException catch (e) {
        if (_isHostLookupError(e)) {
          await _postUri(AppConfig.apiUriWithFallback("/api/session/end"), headers, body);
        } else {
          rethrow;
        }
      }
    } finally {
      clearSessionCache();
      await SessionStore.clearSessionId();
    }
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

  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? "";
    final cachedAt = _cachedMeAt;
    final cached = _cachedMe;
    if (!forceRefresh &&
        userId.isNotEmpty &&
        cached != null &&
        _cachedMeUserId == userId &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _meCacheTtl) {
      return Map<String, dynamic>.from(cached);
    }

    final res = await _get("/api/me");
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _apiError(res);
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    _cachedMeUserId = userId;
    _cachedMeAt = DateTime.now();
    _cachedMe = Map<String, dynamic>.from(jsonMap);
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
    clearUserCache();
    return jsonMap;
  }

  Future<Map<String, dynamic>> updateAdminUser({
    required String userId,
    String username = "",
    String password = "",
  }) async {
    final payload = <String, dynamic>{};
    if (username.trim().isNotEmpty) payload["username"] = username.trim();
    if (password.trim().isNotEmpty) payload["password"] = password;
    final res = await _patch("/api/admin/users/$userId", payload);
    if (res.statusCode < 200 || res.statusCode >= 300) throw _apiError(res);
    clearUserCache();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listUserAccess() async {
    final res = await _get("/api/admin/user-access");
    if (res.statusCode < 200 || res.statusCode >= 300) throw _apiError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patchUserAccess(String userId, Map<String, dynamic> patch) async {
    final res = await _patch("/api/admin/user-access/$userId", patch);
    if (res.statusCode < 200 || res.statusCode >= 300) throw _apiError(res);
    clearUserCache();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listAdminFunTargetStates({int limit = 200}) async {
    final res = await _get("/api/admin/funtarget/states", queryParameters: {"limit": "$limit"});
    if (res.statusCode < 200 || res.statusCode >= 300) throw _apiError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patchAdminFunTargetState(
      String userId, Map<String, dynamic> patch) async {
    final res = await _patch("/api/admin/funtarget/state/$userId", patch);
    if (res.statusCode < 200 || res.statusCode >= 300) throw _apiError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
