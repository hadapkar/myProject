// Web builds cannot self-update; deployments are handled by the hosting platform.
Future<void> downloadAndInstallPlatform({
  required Uri downloadUrl,
  required void Function(double progress01) onProgress,
}) async {
  // No-op on web.
  // (Avoid unused parameter warnings in strict analyzer setups.)
  downloadUrl;
  onProgress(0);
}
