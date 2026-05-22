class TimerAnchor {
  static const int roundSeconds = 60;

  static int computeTimeLeftSeconds(DateTime lastRoundAt, DateTime now) {
    final diffSeconds = now.difference(lastRoundAt).inSeconds;
    final mod = diffSeconds % roundSeconds;
    final left = 59 - mod;
    if (left < 0) return 0;
    if (left > 59) return 59;
    return left;
  }
}

