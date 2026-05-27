import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../services/funtarget_api.dart";
import "../../services/funtarget_models.dart";
import "funtarget_assets.dart";
import "funtarget_sounds.dart";
import "funtarget_stage.dart";
import "timer_anchor.dart";

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _api = FunTargetApi();
  final _sounds = FunTargetSounds();

  FunTargetState? _state;
  String? _error;

  Timer? _timer;
  int _timeLeft = 59;
  int _serverClockOffsetMs = 0;

  // Local UI/game state (mirrors Salesforce behavior; backend is authoritative).
  static const int _segments = 10;
  static const double _segmentAngle = 360 / _segments;
  static const int _spinStartSecond = 0;
  static const int _spinResultSecond = 55;
  static const int _resultHighlightClearSecond = 50;
  static const int _payoutForfeitSecond = 30;
  static const int _finalTenSecond = 10;

  static const String _defaultFooterMessage =
      "You can either Make a Bet or press BET OK button";
  static const String _spinFooterMessage = "For Amusement Only No Cash Value";
  static const String _postSpinFooterMessage =
      "Please bet to Start Game. Minimum Bet - 1";

  int _selectedChip = 1;
  Map<int, int> _betsByNumber = {};
  double _coins = 0;
  double _winnerAmount = 0;
  List<int> _last10Results = const [];
  int? _selectedNumber;
  List<int> _selectedNumbers = [];
  int? _highlightedBetNumber;
  bool _isBetConfirmed = false;
  bool _showPrevBet = false;
  _PrevBetSnapshot? _prevBet;
  double _rotationDegrees = 0;
  bool _isSpinning = false;
  Duration _spinDuration = const Duration(milliseconds: 2800);
  Curve _spinCurve = const Cubic(0.22, 0.9, 0.26, 1.05);
  String _footerMessage = _defaultFooterMessage;

  bool _autoSpinActive = false;
  int? _autoSpinResult;
  bool _roundStartInProgress = false;
  String? _exitSuppressUntilRoundKey;
  String? _spinStartedRoundKey;
  String? _spinFinalizedRoundKey;
  String? _lastRoundAtIso;
  String? _roundEndsAtIso;

  bool _isFinalTenSeconds = false;
  int? _lastTimerSecond;
  bool _loadingSoundPlayed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_sounds.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final state = await _api.getState();
      _applyLoadedState(state);
    } on StateError catch (e) {
      final text = e.message;
      // If session/token is invalid, route back to login (Supabase guard will redirect).
      if (text.contains("Not authenticated") || text.contains("Backend error 401")) {
        if (mounted) {
          setState(() => _error = "Session expired. Please sign in again.");
        }
        await Supabase.instance.client.auth.signOut();
        return;
      }
      setState(() => _error = text);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _applyLoadedState(FunTargetState state) {
    final lastRoundAt = state.lastRoundAt;
    final serverNow = state.serverNow;
    if (serverNow != null) {
      _serverClockOffsetMs =
          serverNow.toUtc().millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;
    }
    final updatedFrom = state.lastUpdatedFrom.trim().toLowerCase();

    final nextLastRoundAtIso = state.lastRoundAt?.toIso8601String();
    final nextRoundEndsAtIso = state.roundEndsAt?.toIso8601String();
    final lastRoundChanged =
        (nextLastRoundAtIso != null && nextLastRoundAtIso != _lastRoundAtIso) ||
            (nextRoundEndsAtIso != null && nextRoundEndsAtIso != _roundEndsAtIso);
    if (lastRoundChanged) {
      _spinStartedRoundKey = null;
      _spinFinalizedRoundKey = null;
      _exitSuppressUntilRoundKey = null;
      _lastTimerSecond = null;
      _lastRoundAtIso = nextLastRoundAtIso;
      _roundEndsAtIso = nextRoundEndsAtIso;
    }
    setState(() {
      _state = state;
      _betsByNumber = state.betsByNumber;
      // Match LWC behavior: avoid overwriting site-side in-round coins with stale server value.
      // Only force-sync coins when updated by an external actor (Admin/Mobile) or when we are
      // not currently in an active bet flow.
      if (updatedFrom == "admin" ||
          updatedFrom == "mobile" ||
          state.betsByNumber.isEmpty) {
        _coins = state.score;
      }
      _winnerAmount = state.winnerAmount;
      _last10Results = state.last10Results;
      _selectedNumbers = _betsByNumber.keys.toList(growable: false);
      _selectedNumber = _selectedNumbers.isEmpty ? null : _selectedNumbers.last;
      _highlightedBetNumber = null;
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    void tick() {
      final state = _state;
      final serverNowMs =
          DateTime.now().millisecondsSinceEpoch + _serverClockOffsetMs;
      final seconds = TimerAnchor.computeTimeLeftSeconds(
        serverNowMs: serverNowMs,
        roundEndsAtMs: state?.roundEndsAt?.millisecondsSinceEpoch,
        lastRoundAtMs: state?.lastRoundAt?.millisecondsSinceEpoch,
        lastModifiedMs: state?.lastModifiedDate?.millisecondsSinceEpoch,
      );
      if (seconds == _timeLeft && seconds == _lastTimerSecond) return;

      final prev = _lastTimerSecond;
      _lastTimerSecond = seconds;

      // Match LWC: prevent upward jumps (except wrap at 0 -> 59).
      final nextSeconds = _clampNoIncrease(prev, seconds);

      setState(() {
        _timeLeft = nextSeconds;
        _isFinalTenSeconds = nextSeconds <= _finalTenSecond;
      });
      _handleTimerSecondChange(prev, nextSeconds);
    }

    tick();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
  }

  int _clampNoIncrease(int? previousSecond, int computedSecond) {
    if (previousSecond == null) return computedSecond;
    if (computedSecond > previousSecond && previousSecond != 0) {
      return previousSecond;
    }
    return computedSecond;
  }

  void _handleTimerSecondChange(int? prev, int curr) {
    // Clear highlight at configured second.
    if (_crossedSecond(prev, curr, _resultHighlightClearSecond)) {
      setState(() => _highlightedBetNumber = null);
    }

    // Forfeit payout after 30s.
    if (_crossedSecond(prev, curr, _payoutForfeitSecond)) {
      final winner = _winnerAmount;
      if (winner > 0) {
        setState(() => _winnerAmount = 0);
        unawaited(_postIntent({"intent": "FORFEIT_PAYOUT"}));
      }
    }

    // Start spin at 0:00.
    if (_crossedSecond(prev, curr, _spinStartSecond)) {
      final roundKey = _getCurrentRoundKey();
      if (roundKey != null) {
        if (_exitSuppressUntilRoundKey == roundKey) return;
        if (_spinStartedRoundKey == roundKey) return;
        _spinStartedRoundKey = roundKey;
      }
      _startAutoSpinRound();
    }

    // Finalize at 0:55.
    if (_autoSpinActive && _crossedSecond(prev, curr, _spinResultSecond)) {
      final roundKey = _getCurrentRoundKey();
      if (roundKey != null) {
        if (_spinFinalizedRoundKey == roundKey) return;
        _spinFinalizedRoundKey = roundKey;
      }
      _finalizeAutoSpinRound();
    }
  }

  bool _crossedSecond(int? prev, int curr, int target) {
    if (prev == null) return curr == target;
    if (prev == curr) return false;
    // Timer counts down: 59..0. Crossing means prev > target and curr <= target,
    // or wrap around (0 -> 59) is handled by the first tick of new round.
    if (prev > target && curr <= target) return true;
    return curr == target;
  }

  String? _getCurrentRoundKey() {
    final state = _state;
    final endsAtMs = state?.roundEndsAt?.millisecondsSinceEpoch;
    if (endsAtMs != null) {
      return (endsAtMs ~/ 1000).toString();
    }
    final anchorMs = state?.lastRoundAt?.millisecondsSinceEpoch;
    if (anchorMs != null) {
      final derivedEndsAtMs = anchorMs + (_spinResultSecond * 1000);
      return (derivedEndsAtMs ~/ 1000).toString();
    }
    return null;
  }

  double _targetAngleForNumber(int value) {
    return 360 - (value * _segmentAngle);
  }

  int _sumBets(Map<int, int> bets) {
    var total = 0;
    for (final v in bets.values) {
      total += v;
    }
    return total;
  }

  Future<void> _postIntent(Map<String, dynamic> payload) async {
    try {
      final next = await _api.postIntent(payload);
      if (!mounted) return;
      _applyLoadedState(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _startAutoSpinRound() {
    if (_autoSpinActive || _roundStartInProgress) return;
    _roundStartInProgress = true;
    try {
      setState(() {
        _highlightedBetNumber = null;
        _isBetConfirmed = true;
        _footerMessage = _spinFooterMessage;
      });

      final predefined = _state?.predefinedWheelNumber;
      final result = predefined ?? Random().nextInt(_segments);
      final targetAngle = _targetAngleForNumber(result);
      final normalized = ((_rotationDegrees % 360) + 360) % 360;
      final delta = (targetAngle - normalized + 360) % 360;

      _autoSpinResult = result;
      _autoSpinActive = true;
      setState(() {
        _isSpinning = true;
        _spinDuration = const Duration(milliseconds: 5000);
        _spinCurve = const Cubic(0.1, 0.95, 0.15, 1.0);
      });
      unawaited(_sounds.stop("wheelStart"));
      unawaited(_sounds.playOnce("wheelStart", FunTargetAssets.soundWheelStart));
      setState(() {
        _rotationDegrees = _rotationDegrees + 12 * 360 + delta;
      });
    } finally {
      _roundStartInProgress = false;
    }
  }

  void _finalizeAutoSpinRound() {
    final result = _autoSpinResult;
    if (!_autoSpinActive || result == null) return;

    final stake = _betsByNumber[result] ?? 0;
    final winValue = stake > 0 ? stake * 9 : 0;
    final nextLast10 =
        [result, ..._last10Results].take(10).toList(growable: false);

    setState(() {
      _highlightedBetNumber = result;
      _isSpinning = false;
      _isBetConfirmed = false;
      _footerMessage = _postSpinFooterMessage;
      _spinDuration = const Duration(milliseconds: 2800);
      _spinCurve = const Cubic(0.22, 0.9, 0.26, 1.05);
      _winnerAmount = winValue.toDouble();
      _betsByNumber = {};
      _selectedNumbers = const [];
      _selectedNumber = null;
      _last10Results = nextLast10;
    });

    unawaited(_sounds.stop("wheelStart"));
    unawaited(_sounds.playOnce("wheelEnd", FunTargetAssets.soundWheelEnd));

    unawaited(_sounds.playOnce(
        winValue > 0 ? "win" : "lose",
        winValue > 0 ? FunTargetAssets.soundWin : FunTargetAssets.soundLose));

    _autoSpinActive = false;
    _autoSpinResult = null;

    unawaited(_postIntent({"intent": "SPIN_RESULT", "spin_result": result}));
  }

  void _onUserGesture() {
    unawaited(_sounds.unlockFromGesture());
    if (!_loadingSoundPlayed) {
      _loadingSoundPlayed = true;
      unawaited(_sounds.playOnce("loading", FunTargetAssets.soundLoading));
    }
    unawaited(_sounds.startClockIfNeeded(FunTargetAssets.soundClock));
  }

  void _selectChip(int chip) {
    _onUserGesture();
    setState(() => _selectedChip = chip);
    unawaited(_sounds.playOnce("button", FunTargetAssets.soundButton));
  }

  void _selectBetNumber(int number) {
    _onUserGesture();
    if (_isSpinning || _isFinalTenSeconds || _isBetConfirmed) return;
    if (_coins < _selectedChip) return;

    final updated = Map<int, int>.from(_betsByNumber);
    updated[number] = (updated[number] ?? 0) + _selectedChip;

    setState(() {
      _betsByNumber = updated;
      _coins = (_coins - _selectedChip).clamp(0, double.infinity);
      _selectedNumbers = updated.keys.toList(growable: false);
      _selectedNumber = number;
      _showPrevBet = false;
      _footerMessage = _defaultFooterMessage;
    });

    unawaited(_sounds.playOnce("bet", FunTargetAssets.soundBet));
    unawaited(_postIntent({"intent": "SYNC_BETS", "bets_json": updated}));
  }

  void _placeBetOk() {
    _onUserGesture();
    final total = _sumBets(_betsByNumber);
    if (total <= 0) return;
    setState(() {
      _isBetConfirmed = true;
      _showPrevBet = false;
      _footerMessage = "Your bet has been Accepted";
      _prevBet = _PrevBetSnapshot(
        betsByNumber: Map<int, int>.from(_betsByNumber),
        selectedChip: _selectedChip,
        selectedNumber: _selectedNumber,
      );
    });
    unawaited(_sounds.playOnce("bet", FunTargetAssets.soundBet));
  }

  void _cancelBet() {
    _onUserGesture();
    final refund = _sumBets(_betsByNumber).toDouble();
    setState(() {
      _selectedNumber = null;
      _selectedNumbers = [];
      _highlightedBetNumber = null;
      _betsByNumber = {};
      _isBetConfirmed = false;
      _footerMessage = _defaultFooterMessage;
      _coins = _coins + refund;
    });
    unawaited(_sounds.playOnce("button", FunTargetAssets.soundButton));
    unawaited(_postIntent({"intent": "SYNC_BETS", "bets_json": const <int, int>{}}));
  }

  void _cancelSpecificBet() {
    _onUserGesture();
    final target = _selectedNumber;
    if (target == null) return;
    final updated = Map<int, int>.from(_betsByNumber);
    final refund = (updated[target] ?? 0).toDouble();
    updated.remove(target);
    setState(() {
      _betsByNumber = updated;
      _coins = _coins + refund;
      _selectedNumbers = updated.keys.toList(growable: false);
      _selectedNumber = null;
      _isBetConfirmed = false;
      _footerMessage = _defaultFooterMessage;
    });
    unawaited(_sounds.playOnce("button", FunTargetAssets.soundButton));
    unawaited(_postIntent({"intent": "SYNC_BETS", "bets_json": updated}));
  }

  void _takePayout() {
    _onUserGesture();
    final pending = _winnerAmount;
    if (pending <= 0) return;
    final projectedScore = _coins + pending;
    unawaited(_sounds.playOnce("take", FunTargetAssets.soundTake));
    setState(() {
      _highlightedBetNumber = null;
      _isBetConfirmed = false;
      _coins = projectedScore;
      _winnerAmount = 0;
      _showPrevBet = _canApplyPrevBetWithScore(projectedScore);
      _footerMessage = _defaultFooterMessage;
    });
    unawaited(_postIntent({"intent": "TAKE_PAYOUT"}));
  }

  bool _canApplyPrevBetWithScore(double availableScore) {
    final prev = _prevBet;
    if (prev == null || prev.betsByNumber.isEmpty) return false;
    if (_isSpinning || _isFinalTenSeconds || _isBetConfirmed) return false;
    final previousTotal = _sumBets(prev.betsByNumber);
    return previousTotal > 0 && availableScore >= previousTotal;
  }

  void _prevBetRestore() {
    _onUserGesture();
    if (_isSpinning || _isFinalTenSeconds || _isBetConfirmed) return;
    final prev = _prevBet;
    if (prev == null || prev.betsByNumber.isEmpty) return;

    final previousTotal = _sumBets(prev.betsByNumber);
    final score = _coins;
    if (score < previousTotal) {
      setState(() {
        _showPrevBet = _canApplyPrevBetWithScore(score);
        _footerMessage = "Not enough coins for previous bet";
      });
      return;
    }

    setState(() {
      _showPrevBet = false;
      _betsByNumber = Map<int, int>.from(prev.betsByNumber);
      _coins = (_coins - previousTotal).clamp(0, double.infinity);
      _selectedNumbers = prev.betsByNumber.keys.toList(growable: false);
      _selectedNumber =
          _selectedNumbers.isEmpty ? prev.selectedNumber : _selectedNumbers.last;
      _selectedChip = prev.selectedChip;
      _footerMessage = _defaultFooterMessage;
    });
    unawaited(_sounds.playOnce("button", FunTargetAssets.soundButton));
    unawaited(
        _postIntent({"intent": "SYNC_BETS", "bets_json": prev.betsByNumber}));
  }

  void _exitToHome() {
    // Exit should not reset state; just navigate back to the tiles page.
    unawaited(_sounds.playOnce("exit", FunTargetAssets.soundExit));
    if (mounted) context.go("/home");
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    final state = _state;
    final email = user?.email ?? "-";
    final totalBet = _sumBets(_betsByNumber);
    final winnerAmount = _winnerAmount;
    final isBettingPhase =
        !_isSpinning && !_isFinalTenSeconds && winnerAmount <= 0;
    final shouldBlinkBetOk =
        isBettingPhase && !_showPrevBet && !_isBetConfirmed && totalBet > 0;
    final betOkDisabled =
        !isBettingPhase || _isBetConfirmed || totalBet <= 0;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onUserGesture,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: state == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text("Loading state..."),
                          ],
                        ),
                      )
                    : SizedBox.expand(
                        child: FunTargetStage(
                          email: email,
                          timeLeftSeconds: _timeLeft,
                          score: _coins,
                          totalBetAmount: totalBet.toDouble(),
                          winnerAmount: _winnerAmount,
                          last10: _last10Results,
                          selectedChip: _selectedChip,
                          onChipSelected: _selectChip,
                          betsByNumber: _betsByNumber,
                          highlightedBetNumber: _highlightedBetNumber,
                          betNumbersDisabled:
                              _isSpinning ||
                              _isFinalTenSeconds ||
                              _isBetConfirmed ||
                              winnerAmount > 0,
                          onBetNumberPressed: _selectBetNumber,
                          isSpinning: _isSpinning,
                          wheelRotationDegrees: _rotationDegrees,
                          wheelSpinDuration: _spinDuration,
                          wheelSpinCurve: _spinCurve,
                          betOkBlink: shouldBlinkBetOk,
                          betOkDisabled: betOkDisabled,
                          takeBlink: winnerAmount > 0,
                          showPrevBet: _showPrevBet,
                          onTake: _takePayout,
                          onCancelBet: _cancelBet,
                          onCancelSpecific: _cancelSpecificBet,
                          onBetOk: _placeBetOk,
                          onPrevBet: _prevBetRestore,
                          onExit: _exitToHome,
                          footerMessage: _footerMessage,
                        ),
                      ),
              ),
              if (_error != null)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Intentionally no Refresh / Sign out buttons on the game screen.
            ],
          ),
        ),
      ),
    );
  }
}

class _PrevBetSnapshot {
  final Map<int, int> betsByNumber;
  final int selectedChip;
  final int? selectedNumber;

  const _PrevBetSnapshot({
    required this.betsByNumber,
    required this.selectedChip,
    required this.selectedNumber,
  });
}
