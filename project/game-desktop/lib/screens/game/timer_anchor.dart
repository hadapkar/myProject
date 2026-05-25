class TimerAnchor {
  static const int roundSeconds = 60;
  static const int spinResultSecond = 55;
  static const int anchorShiftTo59Ms = 56000;

  /// Mirrors the Salesforce LWC timer computation:
  /// - Prefer `roundEndsAt` (server-side end anchor) if present.
  /// - Otherwise use `lastRoundAt` + fallback anchor logic.
  /// - Returns 0..59 (inclusive).
  static int computeTimeLeftSeconds({
    required int serverNowMs,
    int? roundEndsAtMs,
    int? lastRoundAtMs,
    int? lastModifiedMs,
  }) {
    final endsAt = roundEndsAtMs ??
        (lastRoundAtMs == null ? null : (lastRoundAtMs + spinResultSecond * 1000));

    if (endsAt != null) {
      final deltaSeconds = ((endsAt - serverNowMs) / 1000).floor();
      return _positiveMod(deltaSeconds, roundSeconds);
    }

    final anchorMs = lastRoundAtMs ?? _fallbackAnchor(serverNowMs, lastModifiedMs);
    final elapsedSeconds = ((serverNowMs - anchorMs) / 1000).floor().clamp(0, 1 << 30);
    final value =
        (spinResultSecond - (elapsedSeconds % roundSeconds) + roundSeconds) % roundSeconds;
    return value;
  }

  static int _fallbackAnchor(int serverNowMs, int? lastModifiedMs) {
    if (lastModifiedMs != null) {
      return lastModifiedMs - anchorShiftTo59Ms;
    }
    return serverNowMs - anchorShiftTo59Ms;
  }

  static int _positiveMod(int v, int mod) {
    final r = v % mod;
    return r < 0 ? r + mod : r;
  }
}
