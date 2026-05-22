import "dart:async";

import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../services/funtarget_api.dart";
import "../../services/funtarget_models.dart";
import "timer_anchor.dart";

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _api = FunTargetApi();
  FunTargetState? _state;
  String? _error;

  Timer? _timer;
  int _timeLeft = 59;
  DateTime? _lastRoundAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final state = await _api.getState();
      _applyLoadedState(state);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _applyLoadedState(FunTargetState state) {
    final lastRoundAt = state.lastRoundAt;
    setState(() {
      _state = state;
      _lastRoundAt = lastRoundAt;
    });
    _startTimer(lastRoundAt);
  }

  void _startTimer(DateTime? lastRoundAt) {
    _timer?.cancel();
    if (lastRoundAt == null) {
      setState(() => _timeLeft = 59);
      return;
    }

    void tick() {
      final seconds = TimerAnchor.computeTimeLeftSeconds(lastRoundAt, DateTime.now());
      if (seconds == _timeLeft) return;
      setState(() => _timeLeft = seconds);
    }

    tick();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("FunTarget (Flutter)"),
        actions: [
          TextButton(
            onPressed: _signOut,
            child: const Text("Sign out"),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("User: ${user?.email ?? "-"}"),
            const SizedBox(height: 8),
            Text("Timer: 0:${_timeLeft.toString().padLeft(2, "0")}"),
            const SizedBox(height: 12),
            if (_error != null)
              Text("Error: $_error", style: const TextStyle(color: Colors.redAccent)),
            if (_state == null) const Text("Loading state..."),
            if (_state != null) ...[
              Text("Score: ${_state!.score.toStringAsFixed(2)}"),
              Text("Total Bet: ${_state!.totalBetAmount.toStringAsFixed(2)}"),
              Text("Winner: ${_state!.winnerAmount.toStringAsFixed(2)}"),
              Text("Last10: ${_state!.last10Results.join(", ")}"),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _load,
                    child: const Text("Refresh"),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              "Next: implement the full FunTarget UI + logic here, matching the Salesforce LWC 1:1.",
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

