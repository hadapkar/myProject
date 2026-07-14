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
  bool _downloadReady = false;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _busy = true;
      _progress = _downloadReady ? 1 : 0;
      _progressText = _downloadReady ? "Download complete" : "Starting download...";
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
            _progress = hasTotal ? (received / total).clamp(0, 1).toDouble() : null;
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
        _downloadReady = true;
        _progress = 1;
        _progressText = "Download complete";
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
            Text("Current: ${AndroidUpdateService.currentVersion}"),
            Text("Available: ${widget.info.displayVersion}"),
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
            child: Text(
              _busy
                  ? "Downloading..."
                  : (_downloadReady ? "Open installer" : "Download & install"),
            ),
          ),
        ],
      ),
    );
  }
}