import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

typedef UpdateDownloader =
    Future<String> Function(
      Map<String, dynamic> release, {
      required CancelToken cancelToken,
      required void Function(double progress) onProgress,
      String? platform,
    });

/// Pops true once the system installer has opened, false when it could not,
/// and null when the user cancels.
class UpdateDownloadDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> release;
  final String? platform;
  final UpdateDownloader? download;
  final Future<bool> Function(String path)? install;

  const UpdateDownloadDialog({
    super.key,
    required this.release,
    this.platform,
    this.download,
    this.install,
  });

  @override
  ConsumerState<UpdateDownloadDialog> createState() =>
      _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends ConsumerState<UpdateDownloadDialog> {
  final _cancelToken = CancelToken();
  final _progress = ValueNotifier<double?>(null);
  Future<void>? _runFuture;
  bool _closing = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_cancelToken.isCancelled) _runFuture = _run();
    });
  }

  Future<void> _run() async {
    var started = false;
    try {
      if (ref.read(safeModeProvider)) {
        _finish(false);
        return;
      }
      final platform = widget.platform ?? updatePlatform;
      final path = await (widget.download ?? request.downloadUpdate)(
        widget.release,
        platform: platform,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          if (mounted && !_cancelToken.isCancelled) _progress.value = progress;
        },
      );
      if (!mounted || _cancelToken.isCancelled) return;
      if (ref.read(safeModeProvider)) {
        _finish(false);
        return;
      }
      setState(() => _installing = true);
      started =
          await (widget.install?.call(path) ??
              launchUpdateInstaller(
                path,
                platform: platform,
                installAndroid: (path) async =>
                    await app?.installApk(path) == true,
              ));
    } catch (error) {
      if (_cancelToken.isCancelled) return;
      commonPrint.log(
        'update failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
    if (!_cancelToken.isCancelled) _finish(started);
  }

  Future<void> _cancel() async {
    if (_closing || _installing || _cancelToken.isCancelled) return;
    _cancelToken.cancel();
    await _runFuture;
    _finish(null);
  }

  void _finish(bool? result) {
    if (!mounted || _closing) return;
    _closing = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closing = true;
          _cancelToken.cancel();
        } else {
          unawaited(_cancel());
        }
      },
      child: CommonDialog(
        title: context.appLocalizations.updateDownloading,
        actions: [
          TextButton(
            onPressed: _installing ? null : _cancel,
            child: Text(context.appLocalizations.cancel),
          ),
        ],
        child: ValueListenableBuilder(
          valueListenable: _progress,
          builder: (_, progress, _) => LinearProgressIndicator(value: progress),
        ),
      ),
    );
  }
}
