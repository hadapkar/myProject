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
  DateTime? _lastProgressPaint;
  int _lastProgressBytes = 0;

  static const _progressPaintInterval = Duration(milliseconds: 250);
  static const _progressByteStep = 512 * 1024;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _busy = true;
      _progress = _downloadReady ? 1 : 0;
      _progressText = _downloadReady ? "Download complete" : "Starting download...";
      _error = null;
      _status = null;
      _lastProgressPaint = null;
      _lastProgressBytes = 0;
    });

    try {
      await AndroidUpdateService.downloadAndInstall(
        widget.info,
        onProgress: (received, total) {
          if (!mounted) return;
          final now = DateTime.now();
          final complete = total != null && total > 0 && received >= total;
          final shouldPaint = _lastProgressPaint == null ||
              now.difference(_lastProgressPaint!) >= _progressPaintInterval ||
              (received - _lastProgressBytes).abs() >= _progressByteStep ||
              complete;
          if (!shouldPaint) return;

          _lastProgressPaint = now;
          _lastProgressBytes = received;
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
      final errorText = _friendlyUpdateError(e);
      final permissionRequired = errorText.contains("install unknown apps");
      setState(() {
        _busy = false;
        _error = errorText;
        if (permissionRequired) {
          _downloadReady = true;
          _progress = 1;
          _progressText = "Download complete";
        }
      });
    }
  }

  String _friendlyUpdateError(Object error) {
    final text = error.toString().replaceFirst("Bad state: ", "");
    if (text.contains("Network connection interrupted") ||
        text.contains("Connection closed") ||
        text.contains("timed out") ||
        text.contains("incomplete")) {
      return "Download interrupted. Tap retry to continue.";
    }
    return text;
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
            Text("Current: ${AndroidUpdateService.currentDisplayVersion}"),
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
