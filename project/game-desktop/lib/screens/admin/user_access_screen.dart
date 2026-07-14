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
    await _load();
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
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateRow(String userId, {String? status, String? role, String? endsAtIso}) async {
    final payload = <String, dynamic>{};
    if (status != null) payload["status"] = status;
    if (role != null) payload["role"] = role;
    if (endsAtIso != null) payload["ends_at"] = endsAtIso.isEmpty ? null : endsAtIso;
    setState(() => _error = null);
    try {
      await _api.patchUserAccess(userId, payload);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _setEndDateDialog(Map<String, dynamic> row) async {
    final userId = (row["user_id"] ?? "").toString();
    if (userId.isEmpty) return;

    final endsAtStr = (row["ends_at"] ?? "").toString();
    DateTime? initial;
    try {
      if (endsAtStr.isNotEmpty) initial = DateTime.parse(endsAtStr).toLocal();
    } catch (_) {}

    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial ?? DateTime.now(),
    );
    if (picked == null) return;

    // Date-based rule: if "today" matches the end date, block login.
    final localStart = DateTime(picked.year, picked.month, picked.day);
    await _updateRow(userId, endsAtIso: localStart.toUtc().toIso8601String());
  }

  String _roleValue(Map<String, dynamic> row) {
    final role = (row["role"] ?? "PLAYER").toString().toUpperCase();
    return role == "ADMIN" || role == "MANAGER" ? role : "PLAYER";
  }

  String _statusValue(Map<String, dynamic> row) {
    final status = (row["status"] ?? "active").toString().toLowerCase();
    return status == "blocked" ? "blocked" : "active";
  }

  String _formatEndsAt(Map<String, dynamic> row) {
    final endsAt = (row["ends_at"] ?? "").toString();
    if (endsAt.isEmpty) return "-";
    try {
      final date = DateTime.parse(endsAt).toLocal();
      return "${date.year.toString().padLeft(4, "0")}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")}";
    } catch (_) {
      return endsAt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        title: const Text("Subscription Management"),
        actions: [
          IconButton(
            tooltip: "Refresh",
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
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 720) return _mobileList();
                        return _desktopTable(constraints.maxWidth);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileList() {
    if (_rows.isEmpty) return const Center(child: Text("No users found."));
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _UserAccessCard(
        row: _rows[index],
        role: _roleValue(_rows[index]),
        status: _statusValue(_rows[index]),
        endsAt: _formatEndsAt(_rows[index]),
        onRoleChanged: (role) => _updateRow((_rows[index]["user_id"] ?? "").toString(), role: role),
        onSetEndDate: () => _setEndDateDialog(_rows[index]),
        onClearEndDate: () => _updateRow((_rows[index]["user_id"] ?? "").toString(), endsAtIso: ""),
        onToggleStatus: () {
          final userId = (_rows[index]["user_id"] ?? "").toString();
          final status = _statusValue(_rows[index]);
          unawaited(_updateRow(userId, status: status == "active" ? "blocked" : "active"));
        },
      ),
    );
  }

  Widget _desktopTable(double minWidth) {
    if (_rows.isEmpty) return const Center(child: Text("No users found."));
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: SingleChildScrollView(
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
                final role = _roleValue(row);
                final status = _statusValue(row);
                final endsAt = _formatEndsAt(row);
                return DataRow(
                  cells: [
                    DataCell(Text(username)),
                    DataCell(_RoleDropdown(
                      value: role,
                      onChanged: userId.isEmpty ? null : (value) => _updateRow(userId, role: value),
                    )),
                    DataCell(Text(status)),
                    DataCell(Text(endsAt)),
                    DataCell(
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: userId.isEmpty ? null : () => _setEndDateDialog(row),
                            child: const Text("Set end date"),
                          ),
                          OutlinedButton(
                            onPressed: userId.isEmpty ? null : () => _updateRow(userId, endsAtIso: ""),
                            child: const Text("Clear end date"),
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
      ),
    );
  }
}

class _UserAccessCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final String role;
  final String status;
  final String endsAt;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onSetEndDate;
  final VoidCallback onClearEndDate;
  final VoidCallback onToggleStatus;

  const _UserAccessCard({
    required this.row,
    required this.role,
    required this.status,
    required this.endsAt,
    required this.onRoleChanged,
    required this.onSetEndDate,
    required this.onClearEndDate,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final username = (row["username"] ?? "").toString();
    final userId = (row["user_id"] ?? "").toString();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(userId, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          _RoleDropdown(value: role, onChanged: userId.isEmpty ? null : onRoleChanged),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text("Status: $status")),
              OutlinedButton(
                onPressed: userId.isEmpty ? null : onToggleStatus,
                child: Text(status == "active" ? "Block" : "Unblock"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text("End date: $endsAt")),
              OutlinedButton(onPressed: userId.isEmpty ? null : onSetEndDate, child: const Text("Set")),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: userId.isEmpty ? null : onClearEndDate, child: const Text("Clear")),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;

  const _RoleDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value == "ADMIN" || value == "MANAGER" ? value : "PLAYER",
      decoration: const InputDecoration(labelText: "Role"),
      dropdownColor: const Color(0xFF111827),
      items: const [
        DropdownMenuItem(value: "PLAYER", child: Text("Player")),
        DropdownMenuItem(value: "MANAGER", child: Text("Manager")),
        DropdownMenuItem(value: "ADMIN", child: Text("Admin")),
      ],
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value == null || value == this.value) return;
              onChanged!(value);
            },
    );
  }
}
