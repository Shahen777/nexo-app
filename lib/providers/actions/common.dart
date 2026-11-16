part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMonochromeTrayIcon() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(monochromeTrayIcon: !state.monochromeTrayIcon),
        );
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final Map<String, dynamic>? res;
    try {
      res = await request.checkForUpdate(
        mirrorBase: ref.read(appSettingProvider).updateMirror,
      );
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  Future<void> userCheckForUpdate() async {
    if (ref.read(loadingProvider(LoadingTag.checkUpdate))) return;
    final result = await globalState.loadingRun(
      () async => (
        release: await request.checkForUpdate(
          mirrorBase: ref.read(appSettingProvider).updateMirror,
        ),
      ),
      title: currentAppLocalizations.checkUpdate,
      tag: LoadingTag.checkUpdate,
    );
    if (result == null) return;
    await checkUpdateResultHandle(data: result.release, isUser: true);
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: AppTextStyle.title2.of(context),
      children: version == null
          ? [
              TextSpan(text: '\n', style: AppTextStyle.subheadline.of(context)),
              for (final submit in parseReleaseBody(body))
                TextSpan(
                  text: '- $submit \n',
                  style: AppTextStyle.subheadline.of(context),
                ),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                color: group.type == ChangelogType.breaking
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
              ),
        ),
        for (final entry in group.entries)
          TextSpan(
            text: '• ${entry.text}\n',
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    ];
  }

  List<String> _updateUrls(Map<String, dynamic> data) {
    final urls = data['urls'];
    if (urls is! List) return const [];
    return [
      for (final url in urls)
        if (url is String && url.isNotEmpty) url,
    ];
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final urls = _updateUrls(data);
      final context = globalState.navigatorKey.currentContext!;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: _releaseSpan(
          context,
          data['tag_name'] as String,
          data['body'] as String?,
        ),
        confirmText: urls.isEmpty
            ? currentAppLocalizations.goDownload
            : currentAppLocalizations.updateNow,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        if (urls.isEmpty) {
          unawaited(
            launchUrl(
              Uri.parse('https://github.com/$repository/releases/latest'),
            ),
          );
        } else {
          await _downloadAndInstall(data, urls);
        }
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showAlert(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }

  Future<void> _downloadAndInstall(
    Map<String, dynamic> data,
    List<String> urls,
  ) async {
    final sha256 = data['sha256'];
    final name = data['name'];
    if (sha256 is! String || name is! String) return;
    final path = await showUpdateDownloadDialog(
      urls: urls,
      sha256: sha256,
      fileName: name,
    );
    if (path == null) return;
    final result = await installVerifiedUpdate(path);
    switch (result) {
      case UpdateInstallResult.started:
        if (!system.isAndroid) {
          await ref.read(systemActionProvider.notifier).handleExit();
        }
      case UpdateInstallResult.needsPermission:
        unawaited(
          dialogs.showAlert(
            title: currentAppLocalizations.checkUpdate,
            message: TextSpan(
              text: currentAppLocalizations.updatePermissionRequired,
            ),
          ),
        );
      case UpdateInstallResult.failed:
        unawaited(
          dialogs.showAlert(
            title: currentAppLocalizations.checkUpdate,
            message: TextSpan(
              text: currentAppLocalizations.updateInstallFailed,
            ),
          ),
        );
    }
  }
}
