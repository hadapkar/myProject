import "dart:async";

import "package:flutter/material.dart";
import "../../services/funtarget_api.dart";

class UserAccessScreen extends StatefulWidget {
  const UserAccessScreen({super.key});

  @override
  State<UserAccessScreen> createState() => _UserAccessScreenState();
}

class _UserAccessScreenState extends State<UserAccessScreen> {
  final _api = FunTargetApi();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  bool _allowed = false;

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
            content: const Text("You do not have access to Subscription Management."),
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
      _allowed = true;
    } catch (_) {
      _allowed = true; // backend still enforces
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_allowed) return;
      final decoded = await _api.listUserAccess();
      final list = decoded["rows"];
      final rows = <Map<String, dynamic>>[];
      if (list is List) {
        for (final item in list) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      }
      setState(() {
        _rows = rows;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateRow(String userId, {String? status, String? endsAtIso}) async {
    final payload = <String, dynamic>{};
    if (status != null) payload["status"] = status;
    if (endsAtIso != null) {
      payload["ends_at"] = endsAtIso.isEmpty ? null : endsAtIso;
    }
    await _api.patchUserAccess(userId, payload);
    await _load();
  }

  Future<void> _setEndDateDialog(Map<String, dynamic> row) async {
    final userId = (row["user_id"] ?? "").toString();
    if (userId.isEmpty) return;

    final endsAtStr = (row["ends_at"] ?? "").toString();
    DateTime? initial;
    try {
      if (endsAtStr.isNotEmpty) initial = DateTime.parse(endsAtStr);
    } catch (_) {}

    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial ?? DateTime.now(),
    );
    if (picked == null) return;

    // Date-based rule: if "today" matches the end date, block login.
    // Implement by storing the start-of-day (local) as `ends_at`.
    final localStart = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
    final isoUtc = localStart.toUtc().toIso8601String();
    await _updateRow(userId, endsAtIso: isoUtc);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        title: const Text("Subscription Management"),
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
                  : SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text("Username")),
                          DataColumn(label: Text("Role")),
                          DataColumn(label: Text("Status")),
                          DataColumn(label: Text("Ends at")),
                          DataColumn(label: Text("Actions")),
                        ],
                        rows: _rows.map((row) {
                          final userId = (row["user_id"] ?? "").toString();
                          final username = (row["username"] ?? "").toString();
                          final role = (row["role"] ?? "MANAGER").toString();
                          final status = (row["status"] ?? "active").toString();
                          final endsAt = (row["ends_at"] ?? "").toString();
                          return DataRow(
                            cells: [
                              DataCell(Text(username)),
                              DataCell(Text(role)),
                              DataCell(Text(status)),
                              DataCell(Text(endsAt.isEmpty ? "-" : endsAt)),
                              DataCell(
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: userId.isEmpty
                                          ? null
                                          : () => _setEndDateDialog(row),
                                      child: const Text("Set end date"),
                                    ),
                                    OutlinedButton(
                                      onPressed: userId.isEmpty
                                          ? null
                                          : () => _updateRow(
                                                userId,
                                                status: status == "active" ? "blocked" : "active",
                                              ),
                                      child: Text(status == "active" ? "Block" : "Unblock"),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(growable: false),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
