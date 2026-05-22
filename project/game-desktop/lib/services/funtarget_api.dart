import "dart:convert";

import "package:http/http.dart" as http;
import "package:supabase_flutter/supabase_flutter.dart";

import "../config/app_config.dart";
import "funtarget_models.dart";

class FunTargetApi {
  Uri _uri(String path) => Uri.parse("${AppConfig.apiBaseUrl}$path");

  Future<String> _accessToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError("Not authenticated");
    }
    return token;
  }

  Future<FunTargetState> getState() async {
    final token = await _accessToken();
    final res = await http.get(
      _uri("/api/funtarget/state"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Backend error ${res.statusCode}: ${res.body}");
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return FunTargetState.fromJson(jsonMap);
  }

  Future<FunTargetState> postIntent(Map<String, dynamic> payload) async {
    final token = await _accessToken();
    final res = await http.post(
      _uri("/api/funtarget/intent"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Backend error ${res.statusCode}: ${res.body}");
    }
    final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
    return FunTargetState.fromJson(jsonMap);
  }
}
