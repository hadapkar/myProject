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
    await _channel.invokeMethod<bool>("installApk", {"path": apkPath});
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
    await tempFile.rename(apkPath);
    await _channel.invokeMethod<bool>("installApk", {"path": apkPath});
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
