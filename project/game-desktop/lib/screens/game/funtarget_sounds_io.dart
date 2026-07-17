import "dart:io";
import "dart:typed_data";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:just_audio/just_audio.dart";

class FunTargetSounds {
  final Map<String, AudioPlayer> _players = {};
  final Map<String, Process> _windowsLoops = {};
  final Map<String, File> _windowsAssetFiles = {};
  bool _unlocked = false;
  bool _clockStarted = false;
  bool _loggedBackend = false;

  bool get isUnlocked => _unlocked;
  bool get _useWindowsSound => !kIsWeb && Platform.isWindows;

  Future<void> _logOnce(String msg) async {
    if (_loggedBackend) return;
    _loggedBackend = true;
    // ignore: avoid_print
    print("[FunTargetSounds] $msg");
  }

  Future<void> dispose() async {
    for (final process in _windowsLoops.values) {
      try {
        process.kill();
      } catch (_) {
        // ignore
      }
    }
    _windowsLoops.clear();

    for (final p in _players.values) {
      try {
        await p.dispose();
      } catch (_) {
        // ignore
      }
    }
    _players.clear();
    _unlocked = false;
    _clockStarted = false;
  }

  Future<void> unlockFromGesture() async {
    if (_unlocked) return;
    _unlocked = true;
  }

  Future<File> _windowsAssetFile(String assetPath) async {
    final existing = _windowsAssetFiles[assetPath];
    if (existing != null && await existing.exists()) return existing;

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final soundDir = Directory([Directory.systemTemp.path, "kingmaker_sounds"].join(Platform.pathSeparator));
    await soundDir.create(recursive: true);
    final safeName = assetPath.split("/").last.replaceAll(RegExp(r"[^A-Za-z0-9_.-]"), "_");
    final file = File([soundDir.path, safeName].join(Platform.pathSeparator));
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    _windowsAssetFiles[assetPath] = file;
    return file;
  }

  Future<void> _playWindowsOnce(String assetPath) async {
    try {
      final file = await _windowsAssetFile(assetPath);
      final quotedPath = file.path.replaceAll("'", "''");
      await Process.start(
        "powershell.exe",
        [
          "-NoProfile",
          "-NonInteractive",
          "-ExecutionPolicy",
          "Bypass",
          "-WindowStyle",
          "Hidden",
          "-Command",
          "\$p='$quotedPath'; \$player = New-Object System.Media.SoundPlayer \$p; \$player.PlaySync()",
        ],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      await _logOnce("Windows sound failed for $assetPath: $e");
    }
  }

  Future<void> _startWindowsLoop(String key, String assetPath) async {
    if (_windowsLoops.containsKey(key)) return;
    try {
      final file = await _windowsAssetFile(assetPath);
      final quotedPath = file.path.replaceAll("'", "''");
      final process = await Process.start(
        "powershell.exe",
        [
          "-NoProfile",
          "-NonInteractive",
          "-ExecutionPolicy",
          "Bypass",
          "-WindowStyle",
          "Hidden",
          "-Command",
          "\$p='$quotedPath'; \$player = New-Object System.Media.SoundPlayer \$p; while (\$true) { \$player.PlaySync() }",
        ],
      );
      _windowsLoops[key] = process;
    } catch (e) {
      await _logOnce("Windows loop failed for $assetPath: $e");
    }
  }

  Future<void> playOnce(String key, String assetPath) async {
    if (_useWindowsSound) {
      await _playWindowsOnce(assetPath);
      return;
    }

    final player = _players.putIfAbsent(key, () => AudioPlayer());
    try {
      if (player.audioSource == null) {
        await player.setAsset(assetPath);
      }
      await player.seek(Duration.zero);
      await player.setLoopMode(LoopMode.off);
      await player.play();
    } catch (e) {
      await _logOnce("playOnce failed for $assetPath: $e");
    }
  }

  Future<void> startLoop(String key, String assetPath) async {
    if (_useWindowsSound) {
      await _startWindowsLoop(key, assetPath);
      return;
    }

    final player = _players.putIfAbsent(key, () => AudioPlayer());
    try {
      if (player.audioSource == null) {
        await player.setAsset(assetPath);
      }
      await player.setLoopMode(LoopMode.one);
      await player.seek(Duration.zero);
      await player.play();
    } catch (e) {
      await _logOnce("startLoop failed for $assetPath: $e");
    }
  }

  Future<void> stop(String key) async {
    final windowsProcess = _windowsLoops.remove(key);
    if (windowsProcess != null) {
      try {
        windowsProcess.kill();
      } catch (e) {
        await _logOnce("Windows stop failed for $key: $e");
      }
      return;
    }

    final player = _players[key];
    if (player == null) return;
    try {
      await player.stop();
      await player.seek(Duration.zero);
    } catch (e) {
      await _logOnce("stop failed for $key: $e");
    }
  }

  Future<void> startClockIfNeeded(String assetPath) async {
    if (_clockStarted) return;
    _clockStarted = true;
    await startLoop("clock", assetPath);
  }
}