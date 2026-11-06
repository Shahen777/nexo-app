import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Pops true once the system installer has opened, false when it could not,
/// and null when the user cancels.
class UpdateDownloadDialog extends StatefulWidget {
  final Map<String, dynamic> release;

  const UpdateDownloadDialog({super.key, required this.release});

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  final _cancelToken = CancelToken();
  final _progress = ValueNotifier<double?>(null);

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    var started = false;
    try {
      final path = await request.downloadUpdate(
        widget.release,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          if (mounted) _progress.value = progress;
        },
      );
      started = await app?.installApk(path) == true;
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
