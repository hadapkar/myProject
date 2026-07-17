import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../services/android_update_gate.dart";
import "../../services/android_update_service.dart";
import "../../services/update_service.dart";
import "../../services/funtarget_api.dart";
import "../../storage/account_store.dart";
import "../../storage/session_store.dart";
import "../../widgets/profile_avatar.dart";

const _funTargetLogo = "assets/app/logo.jpg";

bool get _desktopUpdatesSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool get _mobileApp =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
String _usernameFromEmail(String email) {
  if (email.trim().isEmpty || email == "-") return "User";
  return email.split("@").first;
}

String _initialsFor(String value) {
  final cleaned = value.trim();
  if (cleaned.isEmpty || cleaned == "-") return "U";
  final parts = cleaned
      .split(RegExp(r"[^A-Za-z0-9]+"))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return cleaned.substring(0, 1).toUpperCase();
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

enum _HomeMenuAction { createUser, subscriptions, updates, guide, signOut }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = FunTargetApi();
  String _role = "PLAYER";
  bool _isAdmin = false;
  bool _canManageFunTarget = false;
  bool _roleLoaded = false;
  String? _homeError;
  bool _guideOpen = false;
  bool _desktopUpdatePromptOpen = false;
  String? _lastPromptedDesktopVersion;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshUserState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(AndroidUpdateGate.maybeShow(context));
    });
    if (_desktopUpdatesSupported) {
      UpdateService.instance.state.addListener(_handleDesktopUpdateState);
      // Background check; UI will show "update available" if needed.
      UpdateService.instance.checkForUpdates();
    }
  }

  @override
  void dispose() {
    if (_desktopUpdatesSupported) {
      UpdateService.instance.state.removeListener(_handleDesktopUpdateState);
    }
    _api.dispose();
    super.dispose();
  }

  void _handleDesktopUpdateState() {
    if (!mounted || !_desktopUpdatesSupported || _desktopUpdatePromptOpen) return;
    final available = UpdateService.instance.state.value.available;
    if (available == null) return;
    if (_lastPromptedDesktopVersion == available.latestTag) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _desktopUpdatePromptOpen) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      final currentAvailable = UpdateService.instance.state.value.available;
      if (currentAvailable == null) return;

      _desktopUpdatePromptOpen = true;
      _lastPromptedDesktopVersion = currentAvailable.latestTag;
      unawaited(
        _openUpdateDialog(automatic: true).whenComplete(() {
          _desktopUpdatePromptOpen = false;
        }),
      );
    });
  }

  String _friendlyBackendMessage(Object error) {
    final text = error.toString();
    if (text.contains("Backend is not responding") ||
        text.contains("Backend request failed") ||
        text.contains("Backend timeout") ||
        text.contains("Failed to fetch")) {
      return "Backend is not responding. Please retry.";
    }
    if (text.contains("session_conflict")) {
      return "This account is active on another device. Please sign in again if needed.";
    }
    if (text.contains("Not authenticated") || text.contains("Backend error 401")) {
      return "Session expired. Please sign in again.";
    }
    return "Unable to load account details. Please retry.";
  }

  Future<void> _refreshUserState({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _roleLoaded = false;
      _homeError = null;
    });

    try {
      final me = await _api.getMe(forceRefresh: force);
      if (!mounted) return;
      final role = (me["role"] ?? "PLAYER").toString().trim().toUpperCase();
      setState(() {
        _role = role == "ADMIN" || role == "MANAGER" || role == "SUPER_PLAYER" ? role : "PLAYER";
        _isAdmin = me["isAdmin"] == true || _role == "ADMIN";
        _canManageFunTarget = me["canManageFunTarget"] == true || _isAdmin || _role == "MANAGER" || _role == "SUPER_PLAYER";
        _roleLoaded = true;
      });
      unawaited(_maybeShowFirstTimeGuide());
    } on StateError catch (e) {
      final msg = e.message;
      if (!mounted) return;
      if (msg.contains("subscription_inactive") || msg.contains("user_blocked")) {
        setState(() => _roleLoaded = true);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("Access unavailable"),
            content: const Text("Please contact admin."),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ],
          ),
        );
        await _removeCurrentAccountProfile();
        await Supabase.instance.client.auth.signOut();
        return;
      }
      setState(() {
        _homeError = _friendlyBackendMessage(e);
        _roleLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _homeError = _friendlyBackendMessage(e);
        _roleLoaded = true;
      });
    }
  }

  Future<void> _openCreateUserDialog() async {
    if (!_isAdmin) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _CreateUserDialog(api: _api),
    );
  }

  void _openUserAccessDashboard() {
    if (!_isAdmin) return;
    context.push("/admin/access");
  }

  Future<void> _endCurrentBackendSession() async {
    try {
      await _api.endSession();
    } catch (_) {
      await SessionStore.clearSessionId();
      _api.clearSessionCache();
    }
  }

  Future<void> _removeCurrentAccountProfile() async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    final email = auth.currentUser?.email ?? session?.user.email ?? "";
    final username = email.contains("@") ? email.split("@").first : email;
    final refreshToken = session?.refreshToken ?? "";
    await AccountStore.removeCurrentAccount(
      email: email,
      username: username,
      refreshToken: refreshToken,
    );
  }

  Future<void> _signOut() async {
    await _removeCurrentAccountProfile();
    await _endCurrentBackendSession();
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _addAccount() async {
    await _endCurrentBackendSession();
    if (!mounted) return;
    context.push("/account-login");
  }

  Future<void> _openAccountMenu() async {
    final accounts = await AccountStore.loadAccounts();
    if (!mounted) return;
    final currentEmail = Supabase.instance.client.auth.currentUser?.email?.toLowerCase() ?? "";
    final action = await showModalBottomSheet<_AccountSheetAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => _AccountSheet(
        accounts: accounts,
        currentEmail: currentEmail,
      ),
    );
    if (action == null || !mounted) return;
    if (action.addAccount) {
      await _addAccount();
      return;
    }
    final account = action.account;
    if (account != null) {
      await _switchToAccount(account);
    }
  }

  Future<void> _switchToAccount(SavedAccount selected) async {
    final currentEmail = Supabase.instance.client.auth.currentUser?.email?.toLowerCase() ?? "";
    if (selected.email.toLowerCase() == currentEmail) return;

    try {
      await _endCurrentBackendSession();
      final response = await Supabase.instance.client.auth.setSession(selected.refreshToken);
      final session = response.session ?? Supabase.instance.client.auth.currentSession;
      if (session == null) throw StateError("Please sign in again");
      final refreshToken = session.refreshToken ?? selected.refreshToken;
      await AccountStore.upsertAccount(
        username: selected.username,
        email: session.user.email ?? selected.email,
        refreshToken: refreshToken,
      );
      if (!mounted) return;
      setState(() {
        _role = "PLAYER";
        _isAdmin = false;
        _canManageFunTarget = false;
        _roleLoaded = false;
      });
      await _refreshUserState(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Switched to ${selected.username}")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in again for this account.")),
      );
    }
  }
  Future<void> _switchRelativeAccount(int offset) async {
    final accounts = await AccountStore.loadAccounts();
    if (!mounted) return;
    if (accounts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add another account to switch.")),
      );
      return;
    }

    final currentEmail = Supabase.instance.client.auth.currentUser?.email?.toLowerCase() ?? "";
    final currentIndex = accounts.indexWhere((account) => account.email.toLowerCase() == currentEmail);
    final start = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (start + offset + accounts.length) % accounts.length;
    await _switchToAccount(accounts[nextIndex]);
  }
  Future<void> _handleMenuAction(_HomeMenuAction action) async {
    switch (action) {
      case _HomeMenuAction.createUser:
        await _openCreateUserDialog();
        return;
      case _HomeMenuAction.subscriptions:
        _openUserAccessDashboard();
        return;
      case _HomeMenuAction.updates:
        await _openUpdateDialog();
        return;
      case _HomeMenuAction.guide:
        await _openGuide();
        return;
      case _HomeMenuAction.signOut:
        await _signOut();
        return;
    }
  }

  Future<void> _openUpdateDialog({bool automatic = false}) async {
    if (!_desktopUpdatesSupported) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return ValueListenableBuilder(
          valueListenable: UpdateService.instance.state,
          builder: (context, UpdateState update, _) {
            final available = update.available;
            return AlertDialog(
              title: Text(automatic ? "Update available" : "Update"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Current: ${UpdateService.currentVersion}"),
                  const SizedBox(height: 8),
                  if (update.checking) const Text("Checking for updates..."),
                  if (update.error != null)
                    Text(update.error!, style: const TextStyle(color: Colors.redAccent)),
                  if (available == null && !update.checking && update.error == null)
                    const Text("No updates available."),
                  if (available != null) Text("Available: ${available.latestTag}"),
                  if (update.installing) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: update.progress01),
                    const SizedBox(height: 8),
                    const Text("Downloading update..."),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: update.installing ? null : () => Navigator.of(context).pop(),
                  child: Text(automatic ? "Later" : "Close"),
                ),
                TextButton(
                  onPressed: update.installing
                      ? null
                      : () => UpdateService.instance.checkForUpdates(force: true),
                  child: const Text("Check"),
                ),
                if (available != null)
                  FilledButton(
                    onPressed: update.installing
                        ? null
                        : () async => UpdateService.instance.downloadAndInstall(),
                    child: const Text("Update now"),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _maybeShowFirstTimeGuide() async {
    if (!mounted || !_roleLoaded || _homeError != null || _guideOpen || _desktopUpdatePromptOpen) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;

    const key = "kingmaker.firstGuide.v2.device";
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) == true) return;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false) || _guideOpen) return;

    _guideOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => _FirstTimeGuideDialog(role: _role),
      );
      await prefs.setBool(key, true);
    } finally {
      _guideOpen = false;
    }
  }

  Future<void> _openGuide() async {
    if (!mounted || _guideOpen) return;
    _guideOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => _FirstTimeGuideDialog(role: _role),
      );
    } finally {
      _guideOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? "-";
    final username = _usernameFromEmail(email);
    final compactActions = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        leadingWidth: 72,
        leading: _ProfileAccountButton(
          initials: _initialsFor(username),
          colorSeed: email == "-" ? username : email,
          onPressed: _openAccountMenu,
          onSwipeUp: () => unawaited(_switchRelativeAccount(-1)),
          onSwipeDown: () => unawaited(_switchRelativeAccount(1)),
        ),
        actions: compactActions ? _compactActions() : _wideActions(email),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshUserState(force: true),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_roleLoaded) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
              ],
              if (_homeError != null) ...[
                _HomeErrorBanner(
                  message: _homeError!,
                  onRetry: () => unawaited(_refreshUserState(force: true)),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width >= 1100
                        ? 4
                        : width >= 820
                            ? 3
                            : width >= 520
                                ? 2
                                : 1;
                    return GridView.count(
                      physics: const AlwaysScrollableScrollPhysics(),
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.4,
                      children: [
                        _GameTile(
                          title: "FunTarget",
                          subtitle: "Wheel / Bet game",
                          imageAsset: _funTargetLogo,
                          onTap: () => context.push("/game"),
                        ),
                        if (_roleLoaded && _canManageFunTarget && _mobileApp)
                          _GameTile(
                            title: "FunTarget Setting",
                            imageAsset: _funTargetLogo,
                            actionLabel: "Open",
                            onTap: () => context.push("/admin/funtarget"),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Version ${AndroidUpdateService.currentDisplayVersion}",
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _wideActions(String email) {
    return [
      if (!_desktopUpdatesSupported && _roleLoaded && _isAdmin)
        TextButton(
          onPressed: _openCreateUserDialog,
          child: const Text("Create User"),
        ),
      if (!_desktopUpdatesSupported && _roleLoaded && _isAdmin)
        TextButton(
          onPressed: _openUserAccessDashboard,
          child: const Text("Subscriptions"),
        ),
      if (_desktopUpdatesSupported)
        ValueListenableBuilder(
          valueListenable: UpdateService.instance.state,
          builder: (context, UpdateState update, _) {
            final hasUpdate = update.available != null;
            final color = hasUpdate ? Colors.amberAccent : Colors.white70;
            return IconButton(
              tooltip: hasUpdate ? "Update available" : "Updates",
              onPressed: _openUpdateDialog,
              icon: Icon(Icons.system_update_alt, color: color),
            );
          },
        ),
      IconButton(
        tooltip: "Guide",
        onPressed: _roleLoaded ? _openGuide : null,
        icon: const Icon(Icons.help_outline),
      ),
      if (!_desktopUpdatesSupported)
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                email,
                style: const TextStyle(color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      TextButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout),
        label: const Text("Sign out"),
      ),
      const SizedBox(width: 8),
    ];
  }

  List<Widget> _compactActions() {
    return [
      PopupMenuButton<_HomeMenuAction>(
        tooltip: "Menu",
        onSelected: (value) => unawaited(_handleMenuAction(value)),
        itemBuilder: (context) => [
          if (!_desktopUpdatesSupported && _roleLoaded && _isAdmin)
            const PopupMenuItem(
              value: _HomeMenuAction.createUser,
              child: Text("Create User"),
            ),
          if (!_desktopUpdatesSupported && _roleLoaded && _isAdmin)
            const PopupMenuItem(
              value: _HomeMenuAction.subscriptions,
              child: Text("Subscriptions"),
            ),
          if (_desktopUpdatesSupported)
            const PopupMenuItem(
              value: _HomeMenuAction.updates,
              child: Text("Updates"),
            ),
          if (_roleLoaded)
            const PopupMenuItem(
              value: _HomeMenuAction.guide,
              child: Text("Guide"),
            ),
          const PopupMenuItem(
            value: _HomeMenuAction.signOut,
            child: Text("Sign out"),
          ),
        ],
      ),
      const SizedBox(width: 8),
    ];
  }
}

class _FirstTimeGuideDialog extends StatefulWidget {
  final String role;

  const _FirstTimeGuideDialog({required this.role});

  @override
  State<_FirstTimeGuideDialog> createState() => _FirstTimeGuideDialogState();
}

class _FirstTimeGuideDialogState extends State<_FirstTimeGuideDialog> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _roleLabel {
    switch (widget.role) {
      case "ADMIN":
        return "Admin";
      case "MANAGER":
        return "Manager";
      case "SUPER_PLAYER":
        return "Super Player";
      default:
        return "Player";
    }
  }

  List<_GuideStep> get _roleSteps {
    switch (widget.role) {
      case "ADMIN":
        return const [
          _GuideStep(
            icon: Icons.group_add_outlined,
            title: "Create users",
            body: "Open the menu and choose Create User to add Player, Super Player, Manager, or Admin accounts.",
          ),
          _GuideStep(
            icon: Icons.manage_accounts_outlined,
            title: "Manage subscriptions",
            body: "Use Subscriptions to update access status, role, parent user, end date, username, password, or delete non-admin users.",
          ),
          _GuideStep(
            icon: Icons.public,
            title: "Full visibility",
            body: "Admins can see all users and can manage the complete hierarchy.",
          ),
        ];
      case "MANAGER":
        return const [
          _GuideStep(
            icon: Icons.admin_panel_settings_outlined,
            title: "Open FunTarget Setting",
            body: "On mobile, use FunTarget Setting to manage assigned players and super players.",
          ),
          _GuideStep(
            icon: Icons.account_tree_outlined,
            title: "Hierarchy based users",
            body: "Your user selector shows only users assigned under your parent hierarchy, so another manager's users stay separate.",
          ),
        ];
      case "SUPER_PLAYER":
        return const [
          _GuideStep(
            icon: Icons.admin_panel_settings_outlined,
            title: "Manage your record",
            body: "On mobile, FunTarget Setting opens for your own game record only.",
          ),
          _GuideStep(
            icon: Icons.person_outline,
            title: "No user selector",
            body: "Super Player access does not show a user selector because this role can manage only itself.",
          ),
        ];
      default:
        return const [
          _GuideStep(
            icon: Icons.home_outlined,
            title: "Player home",
            body: "Your Home page shows the FunTarget game tile and account menu.",
          ),
          _GuideStep(
            icon: Icons.logout,
            title: "Sign out",
            body: "Use the menu to sign out when you finish playing on this device.",
          ),
        ];
    }
  }

  List<_GuideStep> get _steps => [
        _GuideStep(
          icon: Icons.verified_user_outlined,
          title: "Welcome",
          body: "This walkthrough is customized for your current access: $_roleLabel.",
        ),
        const _GuideStep(
          icon: Icons.sports_esports_outlined,
          title: "Play FunTarget",
          body: "Tap the FunTarget tile on Home to open the game. On mobile, the game opens in landscape fullscreen.",
        ),
        ..._roleSteps,
        const _GuideStep(
          icon: Icons.account_circle_outlined,
          title: "Use multiple accounts",
          body: "From Home, tap the profile circle to switch saved accounts or choose Login to new account on the same app.",
        ),
        const _GuideStep(
          icon: Icons.swipe_vertical_outlined,
          title: "Quick account switch",
          body: "Swipe the profile circle up or down to move between saved accounts in order.",
        ),
        const _GuideStep(
          icon: Icons.refresh,
          title: "Refresh data",
          body: "Pull down on supported pages to refresh. Existing refresh buttons are still available where shown.",
        ),
      ];

  Future<void> _goTo(int index) async {
    await _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final isFirst = _index == 0;
    final isLast = _index == steps.length - 1;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = screenHeight < 520 ? 260.0 : (screenHeight < 680 ? 340.0 : 400.0);

    return AlertDialog(
      title: const Text("Walkthrough"),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SizedBox(
          height: maxHeight,
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: steps.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) => _GuideStepCard(
                    step: steps[index],
                    index: index,
                    total: steps.length,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: i == _index ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index ? Colors.deepPurpleAccent.shade100 : Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isLast ? "Close" : "Skip"),
        ),
        TextButton(
          onPressed: isFirst ? null : () => _goTo(_index - 1),
          child: const Text("Back"),
        ),
        FilledButton(
          onPressed: isLast ? () => Navigator.of(context).pop() : () => _goTo(_index + 1),
          child: Text(isLast ? "Done" : "Next"),
        ),
      ],
    );
  }
}

class _GuideStepCard extends StatelessWidget {
  final _GuideStep step;
  final int index;
  final int total;

  const _GuideStepCard({required this.step, required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6D5DF6).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(step.icon, color: Colors.deepPurpleAccent.shade100, size: 28),
                ),
                const Spacer(),
                Text(
                  "${index + 1} / $total",
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              step.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              step.body,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideStep {
  final IconData icon;
  final String title;
  final String body;

  const _GuideStep({required this.icon, required this.title, required this.body});
}

class _HomeErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _HomeErrorBanner({required this.message, required this.onRetry});

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

class _ProfileAccountButton extends StatelessWidget {
  final String initials;
  final String colorSeed;
  final VoidCallback onPressed;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  const _ProfileAccountButton({
    required this.initials,
    required this.colorSeed,
    required this.onPressed,
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) {
            onSwipeUp();
          } else if (velocity > 120) {
            onSwipeDown();
          }
        },
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: ProfileAvatar(initials: initials, seed: colorSeed),
        ),
      ),
    );
  }
}

class _AccountSheetAction {
  final SavedAccount? account;
  final bool addAccount;

  const _AccountSheetAction.switchTo(this.account) : addAccount = false;
  const _AccountSheetAction.add() : account = null, addAccount = true;
}

class _AccountSheet extends StatelessWidget {
  final List<SavedAccount> accounts;
  final String currentEmail;

  const _AccountSheet({required this.accounts, required this.currentEmail});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in accounts.asMap().entries)
              ListTile(
                leading: ProfileAvatar(
                  initials: _initialsFor(entry.value.username),
                  seed: entry.value.email,
                ),
                title: Text(entry.value.username, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: entry.value.email.toLowerCase() == currentEmail
                    ? const Icon(Icons.check, color: Colors.greenAccent)
                    : null,
                onTap: () => Navigator.of(context).pop(_AccountSheetAction.switchTo(entry.value)),
              ),
            if (accounts.isNotEmpty) const Divider(),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text("Login to new account"),
              onTap: () => Navigator.of(context).pop(const _AccountSheetAction.add()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  final FunTargetApi api;

  const _CreateUserDialog({required this.api});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _role = "PLAYER";
  String _parentUserId = "";
  List<Map<String, dynamic>> _parentRows = const [];
  bool _parentsLoading = true;
  DateTime? _endDateLocal;
  bool _busy = false;
  bool _showPassword = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_loadParentRows());
  }

  Future<void> _loadParentRows() async {
    try {
      final decoded = await widget.api.listUserAccess();
      final list = decoded["rows"];
      final rows = <Map<String, dynamic>>[];
      if (list is List) {
        for (final item in list) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      }
      rows.sort((a, b) => _usernameFromRow(a).compareTo(_usernameFromRow(b)));
      if (!mounted) return;
      setState(() {
        _parentRows = rows.where(_canBeParent).toList(growable: false);
        _parentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _parentsLoading = false);
    }
  }

  List<Map<String, dynamic>> get _parentOptions => _parentRows;

  bool _canBeParent(Map<String, dynamic> row) {
    final role = _roleValue(row);
    return role == "ADMIN" || role == "MANAGER";
  }

  String _roleValue(Map<String, dynamic> row) {
    final role = (row["role"] ?? "PLAYER").toString().toUpperCase();
    return role == "ADMIN" || role == "MANAGER" || role == "SUPER_PLAYER" ? role : "PLAYER";
  }

  String _usernameFromRow(Map<String, dynamic> row) => (row["username"] ?? "").toString();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty) {
      setState(() => _message = "Username is required");
      return;
    }
    if (password.length < 6) {
      setState(() => _message = "Password must be at least 6 characters");
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final endsAtIsoUtc = _endDateLocal == null
          ? ""
          : DateTime(
                  _endDateLocal!.year, _endDateLocal!.month, _endDateLocal!.day, 0, 0, 0)
              .toUtc()
              .toIso8601String();
      final res = await widget.api.createUser(
        username: username,
        password: password,
        role: _role,
        endsAt: endsAtIsoUtc,
        parentUserId: _parentUserId,
      );
      final createdUsername = (res["username"] ?? "").toString();
      final createdEmail = (res["email"] ?? "").toString();
      setState(() => _message = "Created user: $createdUsername ($createdEmail)");
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    return AlertDialog(
      title: const Text("Create User"),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: "Username",
                  hintText: "Example: manager01",
                ),
                keyboardType: TextInputType.text,
                scrollPadding: const EdgeInsets.only(bottom: 120),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: "Temporary password",
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? "Hide password" : "Show password",
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                obscureText: !_showPassword,
                scrollPadding: const EdgeInsets.only(bottom: 120),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey(_role),
                initialValue: _role,
                decoration: const InputDecoration(labelText: "Role"),
                items: const [
                  DropdownMenuItem(value: "PLAYER", child: Text("Player")),
                  DropdownMenuItem(value: "MANAGER", child: Text("Manager")),
                  DropdownMenuItem(value: "SUPER_PLAYER", child: Text("Super Player")),
                  DropdownMenuItem(value: "ADMIN", child: Text("Admin")),
                ],
                onChanged: _busy ? null : (v) => setState(() => _role = v ?? "PLAYER"),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _parentUserId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Parent user (optional)"),
                hint: Text(_parentsLoading ? "Loading users..." : "No parent"),
                items: [
                  const DropdownMenuItem<String>(value: "", child: Text("No parent")),
                  ..._parentOptions.map(
                    (row) => DropdownMenuItem<String>(
                      value: (row["user_id"] ?? "").toString(),
                      child: Text(_usernameFromRow(row), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: _busy || _parentsLoading
                    ? null
                    : (v) => setState(() => _parentUserId = v ?? ""),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: "End date (optional)"),
                      child: Text(
                        _endDateLocal == null
                            ? "-"
                            : "${_endDateLocal!.year.toString().padLeft(4, "0")}-"
                                "${_endDateLocal!.month.toString().padLeft(2, "0")}-"
                                "${_endDateLocal!.day.toString().padLeft(2, "0")}",
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate: _endDateLocal ?? DateTime.now(),
                            );
                            if (picked == null) return;
                            if (!mounted) return;
                            setState(() => _endDateLocal = picked);
                          },
                    child: const Text("Pick"),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _endDateLocal = null),
                    child: const Text("Clear"),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.startsWith("Created") ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: Text(_busy ? "Creating..." : "Create"),
        ),
      ],
    );
  }
}

class _GameTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageAsset;
  final VoidCallback onTap;
  final String actionLabel;

  const _GameTile({
    required this.title,
    this.subtitle = "",
    required this.imageAsset,
    required this.onTap,
    this.actionLabel = "Play",
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color.fromRGBO(255, 255, 255, 0.06),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.10)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 96,
                  height: 96,
                  color: const Color.fromRGBO(0, 0, 0, 0.25),
                  child: Image.asset(imageAsset, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white70),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.play_arrow, size: 18, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text(actionLabel, style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
