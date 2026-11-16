import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

Future<String?> showUpdateDownloadDialog({
  required List<String> urls,
  required String sha256,
  required String fileName,
}) {
  return dialogs.showCommonDialog<String>(
    dismissible: false,
    child: _UpdateDownloadDialog(
      urls: urls,
      sha256: sha256,
      fileName: fileName,
    ),
  );
}

class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({
    required this.urls,
    required this.sha256,
    required this.fileName,
  });

  final List<String> urls;
  final String sha256;
  final String fileName;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  final _cancelToken = CancelToken();
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_download());
  }

  Future<void> _download() async {
    try {
      final path = await request.downloadVerifiedUpdate(
        urls: widget.urls,
        sha256Hex: widget.sha256,
        fileName: widget.fileName,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(path);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || !mounted) return;
      setState(() => _error = currentAppLocalizations.updateDownloadFailed);
    } on FormatException {
      if (!mounted) return;
      setState(() => _error = currentAppLocalizations.updateChecksumFailed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = currentAppLocalizations.updateDownloadFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = context.appLocalizations;
    final error = _error;
    return CommonDialog(
      title: localizations.checkUpdate,
      actions: [
        TextButton(
          onPressed: () {
            if (!_cancelToken.isCancelled) _cancelToken.cancel();
            Navigator.of(context).pop();
          },
          child: Text(
            error == null ? localizations.cancel : localizations.confirm,
          ),
        ),
      ],
      child: error == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(localizations.updateDownloading),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
              ],
            )
          : Text(error),
    );
  }
}
