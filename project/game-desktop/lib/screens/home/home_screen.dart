import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../services/update_service.dart";

const _funTargetLogo = "assets/app/logo.jpg";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      // Background check; UI will show "update available" if needed.
      UpdateService.instance.checkForUpdates();
    }
  }

  Future<void> _openUpdateDialog() async {
    if (kIsWeb) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return ValueListenableBuilder(
          valueListenable: UpdateService.instance.state,
          builder: (context, UpdateState update, _) {
            final available = update.available;
            return AlertDialog(
              title: const Text("Update"),
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
                  child: const Text("Close"),
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? "-";

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        title: const Text("Games"),
        actions: [
          if (!kIsWeb)
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
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(email, style: const TextStyle(color: Colors.white70)),
            ),
          ),
          TextButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            child: const Text("Sign out"),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
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
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.4,
              children: [
                _GameTile(
                  title: "FunTarget",
                  subtitle: "Wheel / Bet game",
                  imageAsset: _funTargetLogo,
                  onTap: () => context.go("/game"),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageAsset;
  final VoidCallback onTap;

  const _GameTile({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.onTap,
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
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(Icons.play_arrow, size: 18, color: Colors.white70),
                        SizedBox(width: 6),
                        Text("Play", style: TextStyle(color: Colors.white70)),
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
