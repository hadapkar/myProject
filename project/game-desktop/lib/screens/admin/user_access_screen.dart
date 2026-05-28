import "dart:convert";

import "package:flutter/material.dart";
import "package:http/http.dart" as http;
import "package:supabase_flutter/supabase_flutter.dart";

import "../../config/app_config.dart";

class UserAccessScreen extends StatefulWidget {
  const UserAccessScreen({super.key});

  @override
  State<UserAccessScreen> createState() => _UserAccessScreenState();
}

class _UserAccessScreenState extends State<UserAccessScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _token() async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null || token.isEmpty) throw StateError("Not authenticated");
    return token;
  }

  Uri _uri(String path) => Uri.parse("${AppConfig.apiBaseUrl}$path");

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _token();
      final res = await http.get(
        _uri("/api/admin/user-access"),
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError("Backend error ${res.statusCode}: ${res.body}");
      }
      final decoded = jsonDecode(res.body);
      final list = (decoded is Map<String, dynamic>) ? decoded["rows"] : null;
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
    final token = await _token();
    final payload = <String, dynamic>{};
    if (status != null) payload["status"] = status;
    if (endsAtIso != null) {
      payload["ends_at"] = endsAtIso.isEmpty ? null : endsAtIso;
    }
    final res = await http.patch(
      _uri("/api/admin/user-access/$userId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError("Backend error ${res.statusCode}: ${res.body}");
    }
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
