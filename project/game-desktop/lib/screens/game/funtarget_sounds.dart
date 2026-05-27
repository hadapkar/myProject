import "package:just_audio/just_audio.dart";

class FunTargetSounds {
  final Map<String, AudioPlayer> _players = {};
  bool _unlocked = false;
  bool _clockStarted = false;
  bool _loggedBackend = false;

  bool get isUnlocked => _unlocked;

  Future<void> _logOnce(String msg) async {
    if (_loggedBackend) return;
    _loggedBackend = true;
    // ignore: avoid_print
    print("[FunTargetSounds] $msg");
  }

  Future<void> dispose() async {
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

  Future<void> playOnce(String key, String assetPath) async {
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
