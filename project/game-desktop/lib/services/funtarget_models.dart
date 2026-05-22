class FunTargetState {
  final double score;
  final double totalBetAmount;
  final double winnerAmount;
  final List<int> last10Results;
  final int? predefinedWheelNumber;
  final DateTime? lastRoundAt;

  FunTargetState({
    required this.score,
    required this.totalBetAmount,
    required this.winnerAmount,
    required this.last10Results,
    required this.predefinedWheelNumber,
    required this.lastRoundAt,
  });

  static double _toDouble(Object? value, double fallback) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static int? _toWheelNumber(Object? value) {
    if (value == null) return null;
    final n = (value is num) ? value.toInt() : int.tryParse(value.toString());
    if (n == null || n < 0 || n > 9) return null;
    return n;
  }

  static List<int> _toLast10(Object? value) {
    if (value is List) {
      return value
          .map((e) => (e is num) ? e.toInt() : int.tryParse(e.toString()) ?? -1)
          .where((n) => n >= 0 && n <= 9)
          .take(10)
          .toList(growable: false);
    }
    return const [8, 8, 9, 0, 2, 9, 6, 4, 3, 7];
  }

  static DateTime? _toDateTime(Object? value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString()).toUtc();
    } catch (_) {
      return null;
    }
  }

  factory FunTargetState.fromJson(Map<String, dynamic> json) {
    return FunTargetState(
      score: _toDouble(json["score"], 0),
      totalBetAmount: _toDouble(json["total_bet_amount"], 0),
      winnerAmount: _toDouble(json["winner_amount"], 0),
      last10Results: _toLast10(json["last10_results"]),
      predefinedWheelNumber: _toWheelNumber(json["predefined_wheel_number"]),
      lastRoundAt: _toDateTime(json["last_round_at"]),
    );
  }
}

