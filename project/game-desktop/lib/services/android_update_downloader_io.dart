import "dart:async";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:flutter/services.dart";
import "package:http/http.dart" as http;

const _channel = MethodChannel("kingmaker/android_update");
const _maxDownloadAttempts = 4;
const _maxRedirects = 5;
const _connectTimeout = Duration(seconds: 20);
const _idleTimeout = Duration(seconds: 30);

Future<void> downloadAndInstallApk(
  Uri uri, {
  required String fileName,
  String expectedSha256 = "",
  int expectedBytes = 0,
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
  final tempFile = File("$apkPath.download");
  final normalizedSha = expectedSha256.trim().toLowerCase();
  final existingBytes = await _existingFileLength(file);
  if (existingBytes > 0) {
    if (await _sha256Matches(file, normalizedSha) && _sizeMatches(existingBytes, expectedBytes)) {
      onProgress?.call(existingBytes, _knownTotal(existingBytes, expectedBytes));
      await _openInstaller(file);
      return;
    }
    await _deleteQuietly(file);
  }

  final downloadedFile = await _downloadWithResume(
    uri,
    tempFile,
    expectedBytes: expectedBytes,
    onProgress: onProgress,
  );

  final downloadedBytes = await downloadedFile.length();
  if (!_sizeMatches(downloadedBytes, expectedBytes)) {
    throw StateError("Update download incomplete. Tap retry to continue.");
  }

  if (!await _sha256Matches(downloadedFile, normalizedSha)) {
    await _deleteQuietly(downloadedFile);
    throw StateError("Downloaded update could not be verified. Please retry.");
  }

  if (await file.exists()) await file.delete();
  final readyFile = await downloadedFile.rename(apkPath);
  await _openInstaller(readyFile);
}

Future<File> _downloadWithResume(
  Uri uri,
  File tempFile, {
  required int expectedBytes,
  void Function(int receivedBytes, int? totalBytes)? onProgress,
}) async {
  await tempFile.parent.create(recursive: true);
  var lastError = "";

  for (var attempt = 1; attempt <= _maxDownloadAttempts; attempt++) {
    final client = http.Client();
    IOSink? sink;
    try {
      var startingBytes = await _existingFileLength(tempFile);
      if (expectedBytes > 0 && startingBytes > expectedBytes) {
        await _deleteQuietly(tempFile);
        startingBytes = 0;
      }

      final response = await _sendDownloadRequest(client, uri, startingBytes);
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
          startingBytes > 0 &&
          _sizeMatches(startingBytes, expectedBytes)) {
        onProgress?.call(startingBytes, _knownTotal(startingBytes, expectedBytes));
        return tempFile;
      }

      if (response.statusCode == HttpStatus.partialContent) {
        // Continue the existing partial file.
      } else if (response.statusCode >= 200 && response.statusCode < 300) {
        if (startingBytes > 0) {
          await _deleteQuietly(tempFile);
          startingBytes = 0;
        }
      } else {
        throw StateError("Update download failed (${response.statusCode}).");
      }

      final totalBytes = _totalBytes(response, startingBytes, expectedBytes);
      var received = startingBytes;
      onProgress?.call(received, totalBytes);

      sink = tempFile.openWrite(mode: startingBytes > 0 ? FileMode.append : FileMode.write);
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, totalBytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final actualBytes = await tempFile.length();
      onProgress?.call(actualBytes, _knownTotal(actualBytes, expectedBytes) ?? totalBytes);
      if (_sizeMatches(actualBytes, expectedBytes) || expectedBytes <= 0) {
        return tempFile;
      }
      if (expectedBytes > 0 && actualBytes > expectedBytes) {
        await _deleteQuietly(tempFile);
      }

      lastError = "Update download incomplete.";
    } on TimeoutException {
      lastError = "Update download timed out.";
    } on SocketException {
      lastError = "Network connection interrupted.";
    } on http.ClientException {
      lastError = "Network connection interrupted.";
    } on StateError catch (e) {
      lastError = e.message;
      if (lastError.startsWith("Update download failed")) rethrow;
    } finally {
      await sink?.close();
      client.close();
    }

    if (attempt < _maxDownloadAttempts) {
      await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
    }
  }

  throw StateError("$lastError Tap retry to continue.");
}

Future<http.StreamedResponse> _sendDownloadRequest(
  http.Client client,
  Uri uri,
  int startingBytes,
) async {
  var currentUri = uri;
  for (var redirect = 0; redirect <= _maxRedirects; redirect++) {
    final request = http.Request("GET", currentUri)
      ..followRedirects = false
      ..headers[HttpHeaders.acceptHeader] = "application/vnd.android.package-archive,*/*"
      ..headers[HttpHeaders.userAgentHeader] = "KingMaker Android Updater";
    if (startingBytes > 0) {
      request.headers[HttpHeaders.rangeHeader] = "bytes=$startingBytes-";
    }

    final response = await client.send(request).timeout(_connectTimeout);
    if (!_isRedirect(response.statusCode)) return response;

    final location = response.headers[HttpHeaders.locationHeader.toLowerCase()];
    await response.stream.drain();
    if (location == null || location.trim().isEmpty) {
      throw StateError("Update download redirect failed.");
    }
    currentUri = currentUri.resolve(location);
  }
  throw StateError("Update download redirected too many times.");
}

bool _isRedirect(int statusCode) {
  return statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}

int? _totalBytes(http.StreamedResponse response, int startingBytes, int expectedBytes) {
  if (expectedBytes > 0) return expectedBytes;
  final contentRange = response.headers[HttpHeaders.contentRangeHeader.toLowerCase()];
  final rangeTotal = _parseContentRangeTotal(contentRange);
  if (rangeTotal != null && rangeTotal > 0) return rangeTotal;
  final contentLength = response.contentLength;
  if (contentLength != null && contentLength > 0) return startingBytes + contentLength;
  return null;
}

int? _knownTotal(int currentBytes, int expectedBytes) {
  if (expectedBytes > 0) return expectedBytes;
  return currentBytes > 0 ? currentBytes : null;
}

int? _parseContentRangeTotal(String? value) {
  if (value == null || value.isEmpty) return null;
  final slash = value.lastIndexOf("/");
  if (slash < 0 || slash == value.length - 1) return null;
  final total = value.substring(slash + 1).trim();
  if (total == "*") return null;
  return int.tryParse(total);
}

bool _sizeMatches(int actualBytes, int expectedBytes) {
  return expectedBytes <= 0 || actualBytes == expectedBytes;
}

Future<int> _existingFileLength(File file) async {
  try {
    if (!await file.exists()) return 0;
    return await file.length();
  } catch (_) {
    return 0;
  }
}

Future<bool> _sha256Matches(File file, String expectedSha256) async {
  if (expectedSha256.isEmpty) return true;
  if (!RegExp(r"^[a-f0-9]{64}$").hasMatch(expectedSha256)) {
    throw StateError("Update verification is misconfigured. Please contact admin.");
  }
  try {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedSha256;
  } catch (_) {
    return false;
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
      final match = RegExp(r"^KingMaker-(\d+)\.apk\.download$").firstMatch(name);
      final build = int.tryParse(match?.group(1) ?? "") ?? 0;
      if (build > 0 && build <= currentBuildNumber) await _deleteQuietly(entity);
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