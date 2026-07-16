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
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  bool _allowed = false;
  bool _saving = false;
  String? _selectedUserId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_guardAdmin());
  }

  List<Map<String, dynamic>> get _filteredRows {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _rows;
    return _rows.where((row) {
      final username = (row["username"] ?? "").toString().toLowerCase();
      final userId = (row["user_id"] ?? "").toString().toLowerCase();
      return username.contains(query) || userId.contains(query);
    }).toList(growable: false);
  }

  Map<String, dynamic>? get _selectedRow {
    final selected = _selectedUserId;
    if (selected == null || selected.isEmpty) return null;
    for (final row in _rows) {
      if ((row["user_id"] ?? "").toString() == selected) return row;
    }
    return null;
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

  Future<void> _load({String? keepSelectedUserId}) async {
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
      rows.sort((a, b) => (a["username"] ?? "").toString().compareTo((b["username"] ?? "").toString()));
      if (!mounted) return;
      final wanted = keepSelectedUserId ?? _selectedUserId;
      final selectedStillExists = wanted != null &&
          rows.any((row) => (row["user_id"] ?? "").toString() == wanted);
      setState(() {
        _rows = rows;
        _selectedUserId = selectedStillExists ? wanted : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateRow(String userId, {String? status, String? role, String? endsAtIso}) async {
    if (_saving) return;
    final payload = <String, dynamic>{};
    if (status != null) payload["status"] = status;
    if (role != null) payload["role"] = role;
    if (endsAtIso != null) payload["ends_at"] = endsAtIso.isEmpty ? null : endsAtIso;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.patchUserAccess(userId, payload);
      await _load(keepSelectedUserId: userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Saved.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
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

    final localStart = DateTime(picked.year, picked.month, picked.day);
    await _updateRow(userId, endsAtIso: localStart.toUtc().toIso8601String());
  }

  Future<void> _editUserDialog(Map<String, dynamic> row) async {
    final userId = (row["user_id"] ?? "").toString();
    final username = (row["username"] ?? "").toString();
    if (userId.isEmpty) return;

    final result = await showDialog<_UserEditResult>(
      context: context,
      builder: (context) => _EditUserDialog(initialUsername: username),
    );
    if (result == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.updateAdminUser(
        userId: userId,
        username: result.username,
        password: result.password,
      );
      await _load(keepSelectedUserId: userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User updated.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteUserDialog(Map<String, dynamic> row) async {
    final userId = (row["user_id"] ?? "").toString();
    final username = (row["username"] ?? "").toString();
    if (userId.isEmpty || username.isEmpty || _roleValue(row) == "ADMIN") return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeleteUserDialog(username: username),
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.deleteAdminUser(userId: userId);
      await _load();
      if (!mounted) return;
      setState(() => _selectedUserId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Deleted $username.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  String _roleValue(Map<String, dynamic> row) {
    final role = (row["role"] ?? "PLAYER").toString().toUpperCase();
    return role == "ADMIN" || role == "MANAGER" || role == "SUPER_PLAYER" ? role : "PLAYER";
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
    final selected = _selectedRow;
    final filteredRows = _filteredRows;
    final selectedVisible = _selectedUserId != null &&
        filteredRows.any((row) => (row["user_id"] ?? "").toString() == _selectedUserId);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        title: const Text("Subscription Management"),
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: _loading ? null : () => _load(keepSelectedUserId: _selectedUserId),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(keepSelectedUserId: _selectedUserId),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AccessErrorBanner(
                    message: _error!,
                    onRetry: _loading ? null : () => _load(keepSelectedUserId: _selectedUserId),
                  ),
                ),
              if (_saving) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
              ],
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_rows.isEmpty)
                const Expanded(child: Center(child: Text("No users found.")))
              else
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
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
                            value: selectedVisible ? _selectedUserId : null,
                            decoration: const InputDecoration(labelText: "User name"),
                            hint: const Text("Select user"),
                            dropdownColor: const Color(0xFF111827),
                            items: filteredRows.map((row) {
                              final userId = (row["user_id"] ?? "").toString();
                              final username = (row["username"] ?? "").toString();
                              return DropdownMenuItem<String>(
                                value: userId,
                                child: Text(username, maxLines: 1, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(growable: false),
                            onChanged: _saving ? null : (value) => setState(() => _selectedUserId = value),
                          ),
                          const SizedBox(height: 16),
                          if (selected == null)
                            const Text("Select a user to view and update subscription details.")
                          else
                            _SelectedUserPanel(
                              row: selected,
                              role: _roleValue(selected),
                              status: _statusValue(selected),
                              endsAt: _formatEndsAt(selected),
                              disabled: _saving,
                              onRoleChanged: (role) => _updateRow((selected["user_id"] ?? "").toString(), role: role),
                              onSetEndDate: () => _setEndDateDialog(selected),
                              onClearEndDate: () => _updateRow((selected["user_id"] ?? "").toString(), endsAtIso: ""),
                              onToggleStatus: () {
                                final userId = (selected["user_id"] ?? "").toString();
                                final status = _statusValue(selected);
                                unawaited(_updateRow(userId, status: status == "active" ? "blocked" : "active"));
                              },
                              onEditUser: () => _editUserDialog(selected),
                              canDelete: _roleValue(selected) != "ADMIN",
                              onDeleteUser: () => _deleteUserDialog(selected),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _AccessErrorBanner({required this.message, required this.onRetry});

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

class _SelectedUserPanel extends StatelessWidget {
  final Map<String, dynamic> row;
  final String role;
  final String status;
  final String endsAt;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onSetEndDate;
  final VoidCallback onClearEndDate;
  final VoidCallback onToggleStatus;
  final VoidCallback onEditUser;
  final bool canDelete;
  final VoidCallback onDeleteUser;
  final bool disabled;

  const _SelectedUserPanel({
    required this.row,
    required this.role,
    required this.status,
    required this.endsAt,
    required this.onRoleChanged,
    required this.onSetEndDate,
    required this.onClearEndDate,
    required this.onToggleStatus,
    required this.onEditUser,
    required this.canDelete,
    required this.onDeleteUser,
    required this.disabled,
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
          Text(username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: disabled || userId.isEmpty ? null : onEditUser,
                icon: const Icon(Icons.edit),
                label: const Text("Edit user"),
              ),
              if (canDelete)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: disabled || userId.isEmpty ? null : onDeleteUser,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text("Delete user"),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _RoleDropdown(value: role, onChanged: disabled || userId.isEmpty ? null : onRoleChanged),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text("Status: $status")),
              OutlinedButton(
                onPressed: disabled || userId.isEmpty ? null : onToggleStatus,
                child: Text(status == "active" ? "Block" : "Unblock"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("End date: $endsAt"),
              OutlinedButton(onPressed: disabled || userId.isEmpty ? null : onSetEndDate, child: const Text("Set")),
              OutlinedButton(onPressed: disabled || userId.isEmpty ? null : onClearEndDate, child: const Text("Clear")),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserEditResult {
  final String username;
  final String password;

  const _UserEditResult({required this.username, required this.password});
}

class _EditUserDialog extends StatefulWidget {
  final String initialUsername;

  const _EditUserDialog({required this.initialUsername});

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _username;
  final _password = TextEditingController();
  bool _showPassword = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.initialUsername);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty) {
      setState(() => _message = "Username is required");
      return;
    }
    if (username == widget.initialUsername && password.trim().isEmpty) {
      setState(() => _message = "Change username or enter a new password");
      return;
    }
    if (password.trim().isNotEmpty && password.length < 6) {
      setState(() => _message = "Password must be at least 6 characters");
      return;
    }
    Navigator.of(context).pop(_UserEditResult(username: username, password: password));
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.60;
    return AlertDialog(
      title: const Text("Edit user"),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: "Username"),
                keyboardType: TextInputType.text,
                scrollPadding: const EdgeInsets.only(bottom: 120),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: "New password (optional)",
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? "Hide password" : "Show password",
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                obscureText: !_showPassword,
                scrollPadding: const EdgeInsets.only(bottom: 120),
              ),
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(_message!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text("Save"),
        ),
      ],
    );
  }
}

class _DeleteUserDialog extends StatefulWidget {
  final String username;

  const _DeleteUserDialog({required this.username});

  @override
  State<_DeleteUserDialog> createState() => _DeleteUserDialogState();
}

class _DeleteUserDialogState extends State<_DeleteUserDialog> {
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _confirm.text.trim() == widget.username;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.48;
    return AlertDialog(
      title: const Text("Delete user"),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("This will permanently delete ${widget.username}."),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                decoration: InputDecoration(labelText: "Type ${widget.username} to confirm"),
                scrollPadding: const EdgeInsets.only(bottom: 120),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text("Delete"),
        ),
      ],
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
      value: value == "ADMIN" || value == "MANAGER" || value == "SUPER_PLAYER" ? value : "PLAYER",
      decoration: const InputDecoration(labelText: "Role"),
      dropdownColor: const Color(0xFF111827),
      items: const [
        DropdownMenuItem(value: "PLAYER", child: Text("Player")),
        DropdownMenuItem(value: "MANAGER", child: Text("Manager")),
        DropdownMenuItem(value: "SUPER_PLAYER", child: Text("Super Player")),
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
