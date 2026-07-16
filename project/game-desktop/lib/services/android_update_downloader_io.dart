import "dart:io";

import "package:flutter/services.dart";
import "package:http/http.dart" as http;

const _channel = MethodChannel("kingmaker/android_update");

Future<void> downloadAndInstallApk(
  Uri uri, {
  required String fileName,
  void Function(int receivedBytes, int? totalBytes)? onProgress,
}) async {
  final apkPath = await _channel.invokeMethod<String>(
    "getApkPath",
    {"fileName": fileName},
  );
  if (apkPath == null || apkPath.isEmpty) {
    throw StateError("Unable to prepare update download path.");
  }

  final file = File(apkPath);
  final existingBytes = await _existingFileLength(file);
  if (existingBytes > 0) {
    onProgress?.call(existingBytes, existingBytes);
    await _openInstaller(file);
    return;
  }

  final client = http.Client();
  IOSink? sink;
  final tempFile = File("$apkPath.download");
  try {
    final request = http.Request("GET", uri);
    final response = await client.send(request).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError("Update download failed (${response.statusCode}).");
    }

    await file.parent.create(recursive: true);
    if (await tempFile.exists()) await tempFile.delete();
    sink = tempFile.openWrite();

    var received = 0;
    final total = response.contentLength;
    onProgress?.call(received, total);
    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);
      onProgress?.call(received, total);
    }
    await sink.flush();
    await sink.close();
    sink = null;

    if (total != null && total > 0 && received != total) {
      throw StateError("Update download incomplete. Please retry.");
    }

    if (await file.exists()) await file.delete();
    final downloadedFile = await tempFile.rename(apkPath);
    await _openInstaller(downloadedFile);
  } finally {
    await sink?.close();
    client.close();
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }
}

Future<int> _existingFileLength(File file) async {
  try {
    if (!await file.exists()) return 0;
    return await file.length();
  } catch (_) {
    return 0;
  }
}

Future<void> _openInstaller(File file) async {
  try {
    final opened = await _channel.invokeMethod<bool>("installApk", {"path": file.path});
    if (opened == true) return;
  } on PlatformException catch (_) {
    if (await file.exists()) await file.delete();
    throw StateError("Could not open Android installer. Please retry.");
  }

  if (await file.exists()) await file.delete();
  throw StateError("Could not open Android installer. Please retry.");
}

Future<void> cleanupInstalledApks({required int currentBuildNumber}) async {
  String? apkPath;
  try {
    apkPath = await _channel.invokeMethod<String>(
      "getApkPath",
      {"fileName": "KingMaker-$currentBuildNumber.apk"},
    );
  } catch (_) {
    return;
  }
  if (apkPath == null || apkPath.isEmpty) return;

  final dir = File(apkPath).parent;
  if (!await dir.exists()) return;

  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isEmpty ? "" : entity.uri.pathSegments.last;
    if (name.endsWith(".download")) {
      await _deleteQuietly(entity);
      continue;
    }
    final match = RegExp(r"^KingMaker-(\d+)\.apk$").firstMatch(name);
    if (match == null) continue;
    final build = int.tryParse(match.group(1) ?? "") ?? 0;
    if (build > 0 && build <= currentBuildNumber) {
      await _deleteQuietly(entity);
    }
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {}
}
