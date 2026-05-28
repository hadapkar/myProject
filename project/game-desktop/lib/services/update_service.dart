import "dart:async";
import "dart:convert";

import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;

import "update_service_io.dart"
    if (dart.library.html) "update_service_web.dart";

class UpdateInfo {
  final String latestTag; // e.g. v0.2.0
  final Uri downloadUrl; // zip asset

  const UpdateInfo({required this.latestTag, required this.downloadUrl});
}

class UpdateState {
  final bool checking;
  final UpdateInfo? available;
  final String? error;
  final bool installing;
  final double? progress01;

  const UpdateState({
    required this.checking,
    required this.available,
    required this.error,
    required this.installing,
    required this.progress01,
  });

  static const initial =
      UpdateState(checking: false, available: null, error: null, installing: false, progress01: null);

  UpdateState copyWith({
    bool? checking,
    UpdateInfo? available,
    String? error,
    bool clearError = false,
    bool? installing,
    double? progress01,
  }) {
    return UpdateState(
      checking: checking ?? this.checking,
      available: available ?? this.available,
      error: clearError ? null : (error ?? this.error),
      installing: installing ?? this.installing,
      progress01: progress01 ?? this.progress01,
    );
  }
}

/// GitHub Releases updater (Windows).
///
/// Source of truth is the latest GitHub Release asset named `King Maker.zip`.
class UpdateService {
  static final UpdateService instance = UpdateService._();
  UpdateService._();

  // Hard-coded to avoid spoofing via runtime config.
  static const String _owner = "hadapkar";
  static const String _repo = "myProject";
  // Accept a small set of historical/CI-safe names.
  static const Set<String> _assetNames = {
    "King Maker.zip",
    "King.Maker.zip",
    "KingMaker.zip",
  };

  static const String currentVersion =
      String.fromEnvironment("APP_VERSION", defaultValue: "0.0.0");

  final ValueNotifier<UpdateState> state = ValueNotifier(UpdateState.initial);
  Timer? _debounce;

  Future<void> checkForUpdates({bool force = false}) async {
    if (kIsWeb) return;
    if (!force && (state.value.checking || state.value.installing)) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      state.value = state.value.copyWith(checking: true, clearError: true);
      try {
        final latest = await _fetchLatest();
        final cur = _SemVer.tryParse(_stripV(currentVersion));
        final next = _SemVer.tryParse(_stripV(latest.latestTag));
        if (cur != null && next != null && next.compareTo(cur) > 0) {
          state.value = state.value.copyWith(checking: false, available: latest);
        } else {
          state.value = state.value.copyWith(checking: false, available: null);
        }
      } catch (e) {
        state.value = state.value.copyWith(checking: false, error: e.toString());
      }
    });
  }

  Future<void> downloadAndInstall() async {
    if (kIsWeb) return;
    final info = state.value.available;
    if (info == null) return;
    if (state.value.installing) return;

    state.value = state.value.copyWith(installing: true, progress01: 0, clearError: true);

    try {
      await downloadAndInstallPlatform(
        downloadUrl: info.downloadUrl,
        onProgress: (p) => state.value = state.value.copyWith(progress01: p),
      );
      // If the platform installer returns, it means it decided not to restart.
      state.value = state.value.copyWith(installing: false, progress01: null);
    } catch (e) {
      state.value = state.value.copyWith(installing: false, progress01: null, error: e.toString());
    }
  }

  Future<UpdateInfo> _fetchLatest() async {
    final uri = Uri.parse("https://api.github.com/repos/$_owner/$_repo/releases/latest");
    final res = await http.get(uri, headers: {"User-Agent": "FunTarget"});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Update check failed: ${res.statusCode}");
    }
    final json = jsonDecode(res.body);
    if (json is! Map) throw StateError("Invalid release JSON");

    final tag = (json["tag_name"] ?? "").toString().trim();
    if (tag.isEmpty) throw StateError("Missing tag_name");

    final assets = json["assets"];
    if (assets is! List) throw StateError("Missing assets");

    final foundNames = <String>[];
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a["name"] ?? "").toString();
      if (name.isNotEmpty) foundNames.add(name);
      if (!_assetNames.contains(name)) continue;
      final url = (a["browser_download_url"] ?? "").toString();
      if (url.isEmpty) continue;
      final parsed = Uri.tryParse(url);
      if (parsed == null || parsed.scheme != "https") continue;
      return UpdateInfo(latestTag: tag, downloadUrl: parsed);
    }

    throw StateError(
      "Release asset not found. Expected one of: ${_assetNames.join(', ')}. Found: ${foundNames.join(', ')}",
    );
  }
}

String _stripV(String v) => v.startsWith("v") ? v.substring(1) : v;

class _SemVer implements Comparable<_SemVer> {
  final int major;
  final int minor;
  final int patch;

  const _SemVer(this.major, this.minor, this.patch);

  static _SemVer? tryParse(String v) {
    final m = RegExp(r"^(\d+)\.(\d+)\.(\d+)").firstMatch(v.trim());
    if (m == null) return null;
    return _SemVer(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  @override
  int compareTo(_SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }
}
