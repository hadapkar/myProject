class FunTargetState {
  final double score;
  final double totalBetAmount;
  final double winnerAmount;
  final List<int> last10Results;
  final int? predefinedWheelNumber;
  final DateTime? lastRoundAt;
  final DateTime? roundEndsAt;
  final DateTime? lastModifiedDate;
  final DateTime? serverNow;
  final String lastUpdatedFrom;
  final Map<int, int> betsByNumber;

  FunTargetState({
    required this.score,
    required this.totalBetAmount,
    required this.winnerAmount,
    required this.last10Results,
    required this.predefinedWheelNumber,
    required this.lastRoundAt,
    required this.roundEndsAt,
    required this.lastModifiedDate,
    required this.serverNow,
    required this.lastUpdatedFrom,
    required this.betsByNumber,
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

  static Map<int, int> _toBets(Object? value) {
    if (value is Map) {
      final out = <int, int>{};
      for (final entry in value.entries) {
        final key = int.tryParse(entry.key.toString());
        if (key == null || key < 0 || key > 9) continue;
        final raw = entry.value;
        final n = (raw is num) ? raw.toInt() : int.tryParse(raw.toString());
        if (n == null || n <= 0) continue;
        out[key] = n;
      }
      return out;
    }
    return const {};
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
      lastRoundAt: _toDateTime(json["lastRoundAt"] ?? json["last_round_at"]),
      roundEndsAt: _toDateTime(json["roundEndsAt"]),
      lastModifiedDate: _toDateTime(json["lastModifiedDate"] ?? json["updated_at"]),
      serverNow: _toDateTime(json["serverNow"]),
      lastUpdatedFrom: (json["last_updated_from"] ?? "").toString(),
      betsByNumber: _toBets(json["bets_json"]),
    );
  }
}
