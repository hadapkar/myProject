import "dart:async";

import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../services/funtarget_api.dart";

class _AdminErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _AdminErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 86, 86, 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color.fromRGBO(255, 86, 86, 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white70))),
          TextButton(onPressed: onRetry, child: const Text("Retry")),
        ],
      ),
    );
  }
}
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
  String? _currentUserId;
  bool _roleChecked = false;
  bool _selfOnly = true;

  Map<String, dynamic>? _selected;
  final TextEditingController _amount = TextEditingController(text: "0");
  final TextEditingController _search = TextEditingController();
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
      _currentUserId = (me["id"] ?? "").toString();
      final role = (me["role"] ?? "PLAYER").toString().trim().toUpperCase();
      final canManageFunTarget = me["canManageFunTarget"] == true || me["isAdmin"] == true;
      if (!canManageFunTarget) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("Manager access required"),
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
      if (!mounted) return;
      setState(() {
        _selfOnly = role == "SUPER_PLAYER";
        _roleChecked = true;
      });
    } catch (e) {
      // If we can't verify role, backend will still enforce.
      if (mounted) {
        setState(() {
          _selfOnly = false;
          _roleChecked = true;
        });
      }
    }

    _load();
    _startRealtime();
  }

  @override
  void dispose() {
    _amount.dispose();
    _search.dispose();
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
      final selectedId = (_selected == null ? "" : (_selected!["user_id"] ?? "").toString());
      final defaultId = selectedId.isNotEmpty ? selectedId : (_currentUserId ?? "");
      final selectedRow = _findByIdIn(rows, defaultId);
      setState(() {
        _rows = rows;
        _selected = selectedRow;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _findById(String userId) {
    if (userId.isEmpty) return null;
    for (final r in _selectableRows) {
      if ((r["user_id"] ?? "").toString() == userId) return r;
    }
    return null;
  }

  Map<String, dynamic>? _findByIdIn(List<Map<String, dynamic>> rows, String userId) {
    if (userId.isEmpty) return null;
    for (final r in rows.where(_isActiveUserRow)) {
      if ((r["user_id"] ?? "").toString() == userId) return r;
    }
    return null;
  }

  List<Map<String, dynamic>> get _selectableRows {
    return _rows.where(_isActiveUserRow).toList(growable: false);
  }

  List<Map<String, dynamic>> get _filteredRows {
    final rows = _selectableRows;
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows.where((row) {
      final username = _username(row).toLowerCase();
      final userId = (row["user_id"] ?? "").toString().toLowerCase();
      return username.contains(query) || userId.contains(query);
    }).toList(growable: false);
  }

  bool _isActiveUserRow(Map<String, dynamic> row) {
    final status = (row["access_status"] ?? row["status"] ?? "active")
        .toString()
        .trim()
        .toLowerCase();
    if (status != "active") return false;
    final endsAt = (row["ends_at"] ?? "").toString().trim();
    if (endsAt.isEmpty || endsAt.toLowerCase() == "null") return true;
    final parsed = DateTime.tryParse(endsAt);
    if (parsed == null) return true;
    return parsed.isAfter(DateTime.now());
  }

  String _username(Map<String, dynamic> row) {
    final username = (row["username"] ?? "").toString().trim();
    if (username.isNotEmpty) return username;
    return (row["user_id"] ?? "").toString();
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
    if (mounted) setState(() => _error = null);
    try {
      await _api.patchAdminFunTargetState(userId, payload);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Saved.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final showUserPicker = _roleChecked && !_selfOnly;
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading && _rows.isEmpty) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 12),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AdminErrorBanner(
                  message: _error!,
                  onRetry: _isRefreshDisabled ? null : _load,
                ),
              ),
            if (showUserPicker) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text("Select a user.", style: TextStyle(color: Colors.white70)),
              ),
              _buildUserPicker(selected),
              const SizedBox(height: 12),
            ],
            _buildWheelPanel(selected),
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

  Widget _buildUserPicker(Map<String, dynamic>? selected) {
    final filteredRows = _filteredRows;
    final selectedId = selected == null ? null : (selected["user_id"] ?? "").toString();
    final selectedVisible = selectedId != null &&
        filteredRows.any((row) => (row["user_id"] ?? "").toString() == selectedId);
    final value = selectedVisible ? selectedId : null;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: "Search user",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: "Clear search",
                      onPressed: () => setState(() => _search.clear()),
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            decoration: const InputDecoration(labelText: "Username"),
            hint: Text(_loading ? "Loading users..." : "Select user"),
            items: filteredRows
                .map(
                  (row) => DropdownMenuItem<String>(
                    value: (row["user_id"] ?? "").toString(),
                    child: Text(
                      _username(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .where((item) => item.value != null && item.value!.isNotEmpty)
                .toList(growable: false),
            onChanged: _isRefreshDisabled
                ? null
                : (userId) {
                    if (userId == null) return;
                    setState(() => _selected = _findById(userId));
                  },
          ),
        ],
      ),
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
