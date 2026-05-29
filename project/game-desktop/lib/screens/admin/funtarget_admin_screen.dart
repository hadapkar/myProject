import "package:flutter/material.dart";
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
  final TextEditingController _scoreDelta = TextEditingController(text: "0");
  final TextEditingController _predef = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scoreDelta.dispose();
    _predef.dispose();
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
        if (_selected != null) {
          final id = (_selected!["user_id"] ?? "").toString();
          _selected = rows.where((r) => (r["user_id"] ?? "").toString() == id).cast<Map<String, dynamic>?>().firstWhere((e) => e != null, orElse: () => null);
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _patchSelected({double? scoreDelta, int? predefined, bool clearPredef = false}) async {
    final selected = _selected;
    if (selected == null) return;
    final userId = (selected["user_id"] ?? "").toString();
    if (userId.isEmpty) return;

    final payload = <String, dynamic>{};
    if (scoreDelta != null) payload["score_delta"] = scoreDelta;
    if (clearPredef) payload["clear_predefined"] = true;
    if (predefined != null) payload["predefined_wheel_number"] = predefined;
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
            onPressed: _loading ? null : _load,
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
            Expanded(
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
                        final predef = (r["predefined_wheel_number"] ?? "-").toString();
                        final updatedAt = (r["updated_at"] ?? "").toString();
                        final isSel = selected != null && (selected["user_id"] ?? "").toString() == uid;
                        return ListTile(
                          selected: isSel,
                          onTap: () {
                            setState(() {
                              _selected = r;
                              _predef.text = (r["predefined_wheel_number"] ?? "").toString();
                            });
                          },
                          title: Text(uid, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            "score=$score  totalBet=$totalBet  winner=$winner  predef=$predef\nupdated=$updatedAt",
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            if (selected != null) _buildEditor(selected) else const Text("Select a user row to edit.", style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(Map<String, dynamic> row) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Selected: ${(row["user_id"] ?? "").toString()}", style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _scoreDelta,
                  decoration: const InputDecoration(labelText: "Score delta (ex: 100 or -50)"),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () async {
                  final v = double.tryParse(_scoreDelta.text.trim()) ?? 0;
                  await _patchSelected(scoreDelta: v);
                },
                child: const Text("Apply"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _predef,
                  decoration: const InputDecoration(labelText: "Predefined wheel number (0-9)"),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () async {
                  final n = int.tryParse(_predef.text.trim());
                  if (n == null || n < 0 || n > 9) return;
                  await _patchSelected(predefined: n);
                },
                child: const Text("Set"),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async => _patchSelected(clearPredef: true),
                child: const Text("Clear"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
