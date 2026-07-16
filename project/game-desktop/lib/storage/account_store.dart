import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

class SavedAccount {
  final String username;
  final String email;
  final String refreshToken;
  final DateTime lastUsedAt;

  const SavedAccount({
    required this.username,
    required this.email,
    required this.refreshToken,
    required this.lastUsedAt,
  });

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    return SavedAccount(
      username: (json["username"] ?? "").toString(),
      email: (json["email"] ?? "").toString(),
      refreshToken: (json["refreshToken"] ?? "").toString(),
      lastUsedAt: DateTime.tryParse((json["lastUsedAt"] ?? "").toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        "username": username,
        "email": email,
        "refreshToken": refreshToken,
        "lastUsedAt": lastUsedAt.toUtc().toIso8601String(),
      };
}

class AccountStore {
  static const String _accountsKey = "kingmaker.accounts";

  static Future<List<SavedAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final accounts = <SavedAccount>[];
      for (final item in decoded) {
        if (item is Map) {
          final account = SavedAccount.fromJson(Map<String, dynamic>.from(item));
          if (account.email.isNotEmpty && account.refreshToken.isNotEmpty) {
            accounts.add(account);
          }
        }
      }
      accounts.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      return accounts;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> upsertAccount({
    required String username,
    required String email,
    required String refreshToken,
  }) async {
    if (email.trim().isEmpty || refreshToken.trim().isEmpty) return;
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedUsername = username.trim().isNotEmpty
        ? username.trim()
        : normalizedEmail.split("@").first;
    final accounts = await loadAccounts();
    final account = SavedAccount(
      username: normalizedUsername,
      email: normalizedEmail,
      refreshToken: refreshToken,
      lastUsedAt: DateTime.now().toUtc(),
    );
    final existingIndex = accounts.indexWhere(
      (item) => item.email.toLowerCase() == normalizedEmail,
    );
    final updated = [...accounts];
    if (existingIndex >= 0) {
      updated[existingIndex] = account;
    } else {
      updated.add(account);
    }
    await _save(updated.take(10).toList(growable: false));
  }

  static Future<void> removeAccount(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    final accounts = await loadAccounts();
    await _save(
      accounts
          .where((account) => account.email.toLowerCase() != normalizedEmail)
          .toList(growable: false),
    );
  }

  static Future<void> _save(List<SavedAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _accountsKey,
      jsonEncode(accounts.map((account) => account.toJson()).toList()),
    );
  }
}
