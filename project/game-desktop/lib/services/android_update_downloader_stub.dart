Future<void> downloadAndInstallApk(
  Uri uri, {
  required String fileName,
  String expectedSha256 = "",
  void Function(int receivedBytes, int? totalBytes)? onProgress,
}) async {
  throw UnsupportedError("Android APK download is not supported on this platform.");
}

Future<void> cleanupInstalledApks({required int currentBuildNumber}) async {}