import "dart:io";

import "package:flutter/services.dart";
import "package:http/http.dart" as http;

const _channel = MethodChannel("kingmaker/android_update");

Future<void> downloadAndInstallApk(
  Uri uri, {
  void Function(int receivedBytes, int? totalBytes)? onProgress,
}) async {
  final apkPath = await _channel.invokeMethod<String>("getApkPath");
  if (apkPath == null || apkPath.isEmpty) {
    throw StateError("Unable to prepare update download path.");
  }

  final client = http.Client();
  IOSink? sink;
  try {
    final request = http.Request("GET", uri);
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError("Update download failed (${response.statusCode}).");
    }

    final file = File(apkPath);
    await file.parent.create(recursive: true);
    sink = file.openWrite();

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

    await _channel.invokeMethod<bool>("installApk", {"path": apkPath});
  } finally {
    await sink?.close();
    client.close();
  }
}
