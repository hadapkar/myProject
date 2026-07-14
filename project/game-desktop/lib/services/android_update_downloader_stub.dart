Future<void> downloadAndInstallApk(
  Uri uri, {
  void Function(int receivedBytes, int? totalBytes)? onProgress,
}) async {
  throw UnsupportedError("Android APK download is not supported on this platform.");
}
