import "dart:convert";

import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:url_launcher/url_launcher.dart";

import "../config/app_config.dart";

class AndroidUpdateInfo {
  final bool enabled;
  final String version;
  final int build;
  final String apkUrl;
  final String sha256;
  final bool force;
  final String notes;

  const AndroidUpdateInfo({
    required this.enabled,
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.sha256,
    required this.force,
    required this.notes,
  });

  factory AndroidUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AndroidUpdateInfo(
      enabled: json["enabled"] == true,
      version: (json["version"] ?? "").toString(),
      build: _intValue(json["build"]),
      apkUrl: (json["apkUrl"] ?? "").toString(),
      sha256: (json["sha256"] ?? "").toString(),
      force: json["force"] == true,
      notes: (json["notes"] ?? "").toString(),
    );
  }

  String get displayVersion => version.isEmpty ? "build $build" : "$version+$build";

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? "").toString()) ?? 0;
  }
}

class AndroidUpdateService {
  static const String currentVersion =
      String.fromEnvironment("APP_VERSION", defaultValue: "0.0.0");
  static const int currentBuildNumber =
      int.fromEnvironment("APP_BUILD_NUMBER", defaultValue: 0);

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<AndroidUpdateInfo?> checkForUpdate() async {
    if (!isSupported) return null;

    final uri = AppConfig.apiUri("/public/android/latest");
    final res = await http
        .get(uri, headers: {"Accept": "application/json"})
        .timeout(const Duration(seconds: 10));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Update check failed (${res.statusCode}).");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError("Update check failed (bad response).");
    }

    final info = AndroidUpdateInfo.fromJson(decoded);
    if (!info.enabled || info.build <= currentBuildNumber) return null;
    return info;
  }

  static Future<bool> openUpdate(AndroidUpdateInfo info) async {
    final uri = Uri.tryParse(info.apkUrl);
    if (uri == null || !uri.hasScheme) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
