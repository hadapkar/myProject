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
  static const String _currentAccountEmailKey = "kingmaker.currentAccount.email";
  static const String _currentAccountUsernameKey = "kingmaker.currentAccount.username";
  static const String _currentAccountRefreshTokenKey = "kingmaker.currentAccount.refreshToken";

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
    updated.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    await _save(updated.take(10).toList(growable: false));
    await _saveCurrentAccount(
      email: normalizedEmail,
      username: normalizedUsername,
      refreshToken: refreshToken,
    );
  }

  static Future<void> removeAccount(String emailOrUsername) async {
    final normalized = emailOrUsername.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final accounts = await loadAccounts();
    await _save(
      accounts
          .where((account) {
            final email = account.email.toLowerCase();
            final username = account.username.toLowerCase();
            final localPart = email.split("@").first;
            return email != normalized && username != normalized && localPart != normalized;
          })
          .toList(growable: false),
    );
    await _clearCurrentAccountIfMatches(emailOrUsername: normalized);
  }

  static Future<void> removeAccountByRefreshToken(String refreshToken) async {
    final normalized = refreshToken.trim();
    if (normalized.isEmpty) return;
    final accounts = await loadAccounts();
    await _save(
      accounts
          .where((account) => account.refreshToken.trim() != normalized)
          .toList(growable: false),
    );
    await _clearCurrentAccountIfMatches(refreshToken: normalized);
  }

  static Future<void> removeCurrentAccount({
    String? email,
    String? username,
    String? refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final identifiers = <String>{
      if (email != null && email.trim().isNotEmpty) email.trim().toLowerCase(),
      if (username != null && username.trim().isNotEmpty) username.trim().toLowerCase(),
      if ((email ?? "").contains("@")) email!.trim().toLowerCase().split("@").first,
      (prefs.getString(_currentAccountEmailKey) ?? "").trim().toLowerCase(),
      (prefs.getString(_currentAccountUsernameKey) ?? "").trim().toLowerCase(),
    }..removeWhere((value) => value.isEmpty);

    final tokens = <String>{
      if (refreshToken != null && refreshToken.trim().isNotEmpty) refreshToken.trim(),
      (prefs.getString(_currentAccountRefreshTokenKey) ?? "").trim(),
    }..removeWhere((value) => value.isEmpty);

    if (identifiers.isEmpty && tokens.isEmpty) return;

    final accounts = await loadAccounts();
    await _save(
      accounts
          .where((account) {
            final accountEmail = account.email.toLowerCase();
            final accountUsername = account.username.toLowerCase();
            final accountLocalPart = accountEmail.split("@").first;
            final accountToken = account.refreshToken.trim();
            final identifierMatches = identifiers.contains(accountEmail) ||
                identifiers.contains(accountUsername) ||
                identifiers.contains(accountLocalPart);
            final tokenMatches = tokens.contains(accountToken);
            return !identifierMatches && !tokenMatches;
          })
          .toList(growable: false),
    );
    await _clearCurrentAccount();
  }

  static Future<void> _save(List<SavedAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _accountsKey,
      jsonEncode(accounts.map((account) => account.toJson()).toList()),
    );
  }

  static Future<void> _saveCurrentAccount({
    required String email,
    required String username,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentAccountEmailKey, email.trim().toLowerCase());
    await prefs.setString(_currentAccountUsernameKey, username.trim().toLowerCase());
    await prefs.setString(_currentAccountRefreshTokenKey, refreshToken.trim());
  }

  static Future<void> _clearCurrentAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentAccountEmailKey);
    await prefs.remove(_currentAccountUsernameKey);
    await prefs.remove(_currentAccountRefreshTokenKey);
  }

  static Future<void> _clearCurrentAccountIfMatches({
    String? emailOrUsername,
    String? refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentEmail = (prefs.getString(_currentAccountEmailKey) ?? "").trim().toLowerCase();
    final currentUsername = (prefs.getString(_currentAccountUsernameKey) ?? "").trim().toLowerCase();
    final currentToken = (prefs.getString(_currentAccountRefreshTokenKey) ?? "").trim();
    final normalized = (emailOrUsername ?? "").trim().toLowerCase();
    final token = (refreshToken ?? "").trim();
    final localPart = currentEmail.contains("@") ? currentEmail.split("@").first : "";
    final matchesIdentifier = normalized.isNotEmpty &&
        (normalized == currentEmail || normalized == currentUsername || normalized == localPart);
    final matchesToken = token.isNotEmpty && token == currentToken;
    if (matchesIdentifier || matchesToken) {
      await _clearCurrentAccount();
    }
  }
}
