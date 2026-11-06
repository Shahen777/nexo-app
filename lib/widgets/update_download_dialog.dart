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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  Future<void> _run() async {
    var started = false;
    try {
      if (ref.read(safeModeProvider)) {
        Navigator.of(context).pop(false);
        return;
      }
      final platform = widget.platform ?? updatePlatform;
      final path = await (widget.download ?? request.downloadUpdate)(
        widget.release,
        platform: platform,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          if (mounted) _progress.value = progress;
        },
      );
      if (!mounted || _cancelToken.isCancelled) return;
      if (ref.read(safeModeProvider)) {
        Navigator.of(context).pop(false);
        return;
      }
      started = await (widget.install?.call(path) ??
          launchUpdateInstaller(
            path,
            platform: platform,
            installAndroid: (path) async => await app?.installApk(path) == true,
          ));
    } catch (error) {
      if (_cancelToken.isCancelled) return;
      commonPrint.log(
        'update failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
    if (mounted) Navigator.of(context).pop(started);
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.appLocalizations.updateDownloading,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.appLocalizations.cancel),
        ),
      ],
      child: ValueListenableBuilder(
        valueListenable: _progress,
        builder: (_, progress, _) => LinearProgressIndicator(value: progress),
      ),
    );
  }
}
