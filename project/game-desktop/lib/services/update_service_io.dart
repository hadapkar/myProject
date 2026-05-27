import "dart:async";
import "dart:io";

Future<void> downloadAndInstallPlatform({
  required Uri downloadUrl,
  required void Function(double progress01) onProgress,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError("Auto-update is currently supported on Windows only.");
  }

  final appExePath = Platform.resolvedExecutable;
  final appDir = Directory(File(appExePath).parent.path);
  final appExeName = File(appExePath).uri.pathSegments.isEmpty
      ? "FunTarget.exe"
      : File(appExePath).uri.pathSegments.last;

  final tempDir = await Directory.systemTemp.createTemp("funtarget_update_");
  final zipPath = "${tempDir.path}\\King Maker.zip";
  final extractDir = Directory("${tempDir.path}\\extracted");

  try {
    await _downloadFile(
      url: downloadUrl,
      outFile: File(zipPath),
      onProgress: onProgress,
    );

    await extractDir.create(recursive: true);
    await _expandZipWindows(zipPath: zipPath, outDir: extractDir.path);

    // The release zip contains the full Windows "Release" folder contents at root.
    // We'll copy it into the app directory after the app exits, then restart.
    final scriptPath = "${tempDir.path}\\apply_update.bat";
    final script = _buildWindowsUpdateScript(
      fromDir: extractDir.path,
      toDir: appDir.path,
      exeName: appExeName,
      tempDir: tempDir.path,
    );
    await File(scriptPath).writeAsString(script, flush: true);

    await Process.start(
      "cmd.exe",
      ["/c", scriptPath],
      mode: ProcessStartMode.detached,
      workingDirectory: tempDir.path,
    );

    // Exit the app so the script can overwrite the running executable.
    exit(0);
  } catch (_) {
    // Best-effort cleanup for failures.
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
    rethrow;
  }
}

Future<void> _downloadFile({
  required Uri url,
  required File outFile,
  required void Function(double progress01) onProgress,
}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    final res = await req.close();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Update download failed: HTTP ${res.statusCode}");
    }

    final total = res.contentLength > 0 ? res.contentLength : null;
    var received = 0;
    final sink = outFile.openWrite();
    try {
      await for (final chunk in res) {
        received += chunk.length;
        sink.add(chunk);
        if (total != null) {
          onProgress((received / total).clamp(0, 1));
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total == null) onProgress(1);
  } finally {
    client.close(force: true);
  }
}

Future<void> _expandZipWindows({
  required String zipPath,
  required String outDir,
}) async {
  // Use PowerShell's Expand-Archive (available on modern Windows).
  final ps = [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    "Expand-Archive -LiteralPath '${zipPath.replaceAll("'", "''")}' -DestinationPath '${outDir.replaceAll("'", "''")}' -Force",
  ];
  final result = await Process.run("powershell.exe", ps);
  if (result.exitCode != 0) {
    throw StateError("Failed to extract update zip: ${result.stderr}");
  }
}

String _buildWindowsUpdateScript({
  required String fromDir,
  required String toDir,
  required String exeName,
  required String tempDir,
}) {
  final f = fromDir.replaceAll("/", "\\");
  final t = toDir.replaceAll("/", "\\");
  final tmp = tempDir.replaceAll("/", "\\");
  return """
@echo off
setlocal enabledelayedexpansion

REM Wait briefly for the app to exit.
ping 127.0.0.1 -n 3 >nul

REM Copy new build over existing folder.
xcopy /E /I /Y "$f\\*" "$t\\" >nul
if errorlevel 1 (
  echo Update copy failed. Please reinstall from the latest release.
  exit /b 1
)

REM Restart the app.
start "" "$t\\$exeName"

REM Cleanup temp directory.
rmdir /S /Q "$tmp" >nul 2>&1

endlocal
exit /b 0
""";
}
