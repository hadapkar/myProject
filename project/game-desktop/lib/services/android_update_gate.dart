import "package:flutter/material.dart";

import "android_update_service.dart";

class AndroidUpdateGate {
  static bool _showing = false;
  static bool _dismissedOptionalUpdate = false;

  static bool _canShow(BuildContext context) {
    if (!context.mounted) return false;
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  static Future<void> maybeShow(BuildContext context) async {
    if (_showing || _dismissedOptionalUpdate || !_canShow(context)) return;

    AndroidUpdateInfo? info;
    try {
      info = await AndroidUpdateService.checkForUpdate();
    } catch (_) {
      return;
    }
    if (info == null || !_canShow(context)) return;

    _showing = true;
    try {
      final dismissed = await showDialog<bool>(
        context: context,
        barrierDismissible: !info.force,
        builder: (context) => _AndroidUpdateDialog(info: info!),
      );
      if (dismissed == true && !info.force) {
        _dismissedOptionalUpdate = true;
      }
    } finally {
      _showing = false;
    }
  }
}

class _AndroidUpdateDialog extends StatefulWidget {
  final AndroidUpdateInfo info;

  const _AndroidUpdateDialog({required this.info});

  @override
  State<_AndroidUpdateDialog> createState() => _AndroidUpdateDialogState();
}

class _AndroidUpdateDialogState extends State<_AndroidUpdateDialog> {
  bool _busy = false;
  double? _progress;
  String? _progressText;
  String? _error;
  String? _status;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _busy = true;
      _progress = null;
      _progressText = "Preparing download...";
      _error = null;
      _status = null;
    });

    try {
      await AndroidUpdateService.downloadAndInstall(
        widget.info,
        onProgress: (received, total) {
          if (!mounted) return;
          final hasTotal = total != null && total > 0;
          setState(() {
            _progress = hasTotal ? received / total : null;
            _progressText = hasTotal
                ? "${AndroidUpdateService.formatBytes(received)} of ${AndroidUpdateService.formatBytes(total)}"
                : AndroidUpdateService.formatBytes(received);
          });
        },
      );
      if (!mounted) return;
      if (!widget.info.force) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _busy = false;
        _progress = 1;
        _status = "Installer opened. Complete installation to continue.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final force = widget.info.force;
    return WillPopScope(
      onWillPop: () async => !force && !_busy,
      child: AlertDialog(
        title: Text(force ? "Update required" : "Update available"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              force
                  ? "Install the latest Android version before continuing."
                  : "A newer Android version is available.",
            ),
            const SizedBox(height: 12),
            Text(
              "Current: ${AndroidUpdateService.currentVersion}",
            ),
            Text("Available: ${widget.info.displayVersion}"),
            if (widget.info.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(widget.info.notes),
            ],
            if (_busy || _progressText != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_progressText ?? "Downloading..."),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!, style: const TextStyle(color: Colors.white70)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
        actions: [
          if (!force)
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(true),
              child: const Text("Later"),
            ),
          FilledButton(
            onPressed: _busy ? null : _downloadAndInstall,
            child: Text(_busy ? "Downloading..." : "Download & install"),
          ),
        ],
      ),
    );
  }
}
