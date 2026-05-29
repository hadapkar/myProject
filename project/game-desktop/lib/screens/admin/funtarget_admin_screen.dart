import "dart:async";

import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../services/funtarget_api.dart";

class FunTargetAdminScreen extends StatefulWidget {
  const FunTargetAdminScreen({super.key});

  @override
  State<FunTargetAdminScreen> createState() => _FunTargetAdminScreenState();
}

class _FunTargetAdminScreenState extends State<FunTargetAdminScreen> {
  final _api = FunTargetApi();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  Map<String, dynamic>? _selected;
  final TextEditingController _amount = TextEditingController(text: "0");
  bool _isSaving = false;
  bool _isWheelSaving = false;

  RealtimeChannel? _channel;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    unawaited(_guardAdmin());
  }

  Future<void> _guardAdmin() async {
    try {
      final me = await _api.getMe();
      final isAdmin = me["isAdmin"] == true;
      if (!isAdmin) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("Admins only"),
            content: const Text("You do not have access to FunTarget Admin."),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      // If we can't verify role, backend will still enforce.
    }

    _load();
    _startRealtime();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reloadDebounce?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final decoded = await _api.listAdminFunTargetStates(limit: 200);
      final list = decoded["rows"];
      final rows = <Map<String, dynamic>>[];
      if (list is List) {
        for (final item in list) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      }
      setState(() {
        _rows = rows;
        if (_selected != null) _selected = _findById((_selected!["user_id"] ?? "").toString());
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _findById(String userId) {
    if (userId.isEmpty) return null;
    for (final r in _rows) {
      if ((r["user_id"] ?? "").toString() == userId) return r;
    }
    return null;
  }

  void _startRealtime() {
    final supabase = Supabase.instance.client;
    _channel = supabase
        .channel("admin-funtarget")
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: "public",
          table: "fun_target_state",
          callback: (payload) {
            _reloadDebounce?.cancel();
            _reloadDebounce = Timer(const Duration(milliseconds: 350), () {
              if (mounted) _load();
            });
          },
        )
        .subscribe();
  }

  bool get _isRefreshDisabled => _loading || _isSaving || _isWheelSaving;

  Future<void> _patchSelected({double? scoreDelta, int? predefined, bool clearPredef = false, bool resetScore = false}) async {
    final selected = _selected;
    if (selected == null) return;
    final userId = (selected["user_id"] ?? "").toString();
    if (userId.isEmpty) return;

    final payload = <String, dynamic>{};
    if (scoreDelta != null) payload["score_delta"] = scoreDelta;
    if (clearPredef) payload["clear_predefined"] = true;
    if (predefined != null) payload["predefined_wheel_number"] = predefined;
    if (resetScore) {
      final current = double.tryParse((selected["score"] ?? "0").toString()) ?? 0;
      payload["score_delta"] = -current;
    }
    await _api.patchAdminFunTargetState(userId, payload);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        title: const Text("FunTarget Admin"),
        actions: [
          IconButton(
            onPressed: _isRefreshDisabled ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            if (selected == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text("Select a user from Live Bets below.", style: TextStyle(color: Colors.white70)),
              ),
            _buildWheelPanel(selected),
            const SizedBox(height: 12),
            _buildLivePanel(selected),
            const SizedBox(height: 12),
            _buildScorePanel(selected),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.10)),
      ),
      child: child,
    );
  }

  Widget _buildWheelPanel(Map<String, dynamic>? selected) {
    final selectedValue = selected == null ? null : selected["predefined_wheel_number"];
    final selectedInt = selectedValue == null ? null : int.tryParse(selectedValue.toString());
    final disabled = selected == null || _isRefreshDisabled;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Predefined Wheel Number", style: TextStyle(color: Colors.white70)),
              TextButton(
                onPressed: disabled || selectedInt == null ? null : () async {
                  setState(() => _isWheelSaving = true);
                  try {
                    await _patchSelected(clearPredef: true);
                  } finally {
                    if (mounted) setState(() => _isWheelSaving = false);
                  }
                },
                child: const Text("Reset"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _wheelRow([1, 2, 3, 4, 5], selectedInt, disabled),
          const SizedBox(height: 8),
          _wheelRow([6, 7, 8, 9, 0], selectedInt, disabled),
        ],
      ),
    );
  }

  Widget _wheelRow(List<int> nums, int? selected, bool disabled) {
    return Row(
      children: nums.map((n) {
        final isSel = selected != null && selected == n;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: OutlinedButton(
              onPressed: disabled || isSel
                  ? null
                  : () async {
                      setState(() => _isWheelSaving = true);
                      try {
                        await _patchSelected(predefined: n);
                      } finally {
                        if (mounted) setState(() => _isWheelSaving = false);
                      }
                    },
              style: OutlinedButton.styleFrom(
                backgroundColor: isSel ? const Color.fromRGBO(255, 255, 255, 0.18) : null,
              ),
              child: Text("$n"),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildLivePanel(Map<String, dynamic>? selected) {
    return Expanded(
      child: _card(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final r = _rows[index];
                  final uid = (r["user_id"] ?? "").toString();
                  final score = (r["score"] ?? 0).toString();
                  final totalBet = (r["total_bet_amount"] ?? 0).toString();
                  final winner = (r["winner_amount"] ?? 0).toString();
                  final updatedAt = (r["updated_at"] ?? "").toString();
                  final isSel = selected != null && (selected["user_id"] ?? "").toString() == uid;
                  return ListTile(
                    dense: true,
                    selected: isSel,
                    onTap: _isRefreshDisabled
                        ? null
                        : () => setState(() => _selected = r),
                    title: Text(uid, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      "score=$score  totalBet=$totalBet  winner=$winner\nupdated=$updatedAt",
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildScorePanel(Map<String, dynamic>? selected) {
    final score = selected == null ? 0.0 : (double.tryParse((selected["score"] ?? "0").toString()) ?? 0.0);
    final updatedFrom = selected == null ? "-" : (selected["last_updated_from"] ?? "-").toString();
    final updatedAt = selected == null ? "-" : (selected["updated_at"] ?? "-").toString();
    final disabled = selected == null || _isRefreshDisabled;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Current Score", style: TextStyle(color: Colors.white70)),
              Text(score.toStringAsFixed(2), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: "Amount to Add"),
            keyboardType: TextInputType.number,
            enabled: !disabled,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: disabled
                      ? null
                      : () async {
                          final v = double.tryParse(_amount.text.trim()) ?? 0;
                          if (v <= 0) return;
                          setState(() => _isSaving = true);
                          try {
                            await _patchSelected(scoreDelta: v);
                            _amount.text = "0";
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  child: const Text("Add"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: disabled
                      ? null
                      : () async {
                          setState(() => _isSaving = true);
                          try {
                            await _patchSelected(resetScore: true);
                            _amount.text = "0";
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  child: const Text("Reset Score"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text("Updated From: $updatedFrom", style: const TextStyle(color: Colors.white70)),
          Text("Last Updated: $updatedAt", style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
