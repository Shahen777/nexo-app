part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;
  bool _updateInProgress = false;

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

  @protected
  String? get updateHostPlatform => updatePlatform;

  @protected
  DesktopUpdater get desktopUpdater => const DesktopUpdater();

  @protected
  Future<Map<String, dynamic>?> fetchUpdateRelease() => request.checkForUpdate();

  @protected
  Future<void> clearDownloadedUpdate() => request.removeDownloadedUpdate();

  Future<T?> _runUpdateOperation<T>(Future<T> Function() operation) async {
    if (ref.read(safeModeProvider) || _updateInProgress) return null;
    _updateInProgress = true;
    try {
      return await operation();
    } finally {
      _updateInProgress = false;
    }
  }

  Future<void> checkUpdate() async {
    if (ref.read(loadingProvider(LoadingTag.checkUpdate))) return;
    await _runUpdateOperation<void>(() async {
      if (updateHostPlatform == 'macos') {
        await globalState.loadingRun(
          () => desktopUpdater.checkForUpdates(
            manifestUrl: updateManifestUrl,
            background: false,
            safeMode: ref.read(safeModeProvider),
          ),
          title: currentAppLocalizations.checkUpdate,
          tag: LoadingTag.checkUpdate,
        );
        return;
      }
      final result = await globalState.loadingRun(
        () async => (release: await fetchUpdateRelease()),
        title: currentAppLocalizations.checkUpdate,
        tag: LoadingTag.checkUpdate,
      );
      if (result == null) return;
      await _handleUpdateResult(data: result.release, isUser: true);
    });
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    return await _runUpdateOperation<bool>(() async {
      try {
        if (updateHostPlatform == 'macos') {
          return await desktopUpdater.checkForUpdates(
            manifestUrl: updateManifestUrl,
            background: true,
            safeMode: ref.read(safeModeProvider),
          );
        }
        if (updateHostPlatform == 'windows' ||
            updateHostPlatform?.startsWith('android-') == true) {
          await clearDownloadedUpdate();
        }
        final release = await fetchUpdateRelease();
        await _handleUpdateResult(data: release);
        return release != null;
      } catch (error) {
        commonPrint.log(
          'checkForUpdate failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
        return false;
      }
    }) ?? false;
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

  Future<void> _applyUpdate(Map<String, dynamic> release) async {
    if (ref.read(safeModeProvider)) return;
    final platform = updateHostPlatform;
    if (platform != 'windows' &&
        platform?.startsWith('android-') != true) {
      await launchUrl(
        Uri.parse(release['url'] as String),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    final started = await downloadAndInstallUpdate(release, platform: platform);
    if (started == true && platform == 'windows') {
      await ref.read(systemActionProvider.notifier).handleExit();
    } else if (started == false) {
      await dialogs.showAlert(
        title: currentAppLocalizations.checkUpdate,
        message: TextSpan(text: currentAppLocalizations.updateFailed),
      );
    }
  }

  @protected
  Future<bool?> downloadAndInstallUpdate(
    Map<String, dynamic> release, {
    required String? platform,
  }) => dialogs.showCommonDialog<bool>(
    dismissible: false,
    child: UpdateDownloadDialog(release: release, platform: platform),
  );

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    await _runUpdateOperation<void>(
      () => _handleUpdateResult(data: data, isUser: isUser),
    );
  }

  Future<void> _handleUpdateResult({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (ref.read(safeModeProvider)) return;
    if (data != null) {
      final context = globalState.navigatorKey.currentContext!;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: TextSpan(
          children: [
            _releaseSpan(
              context,
              data['tag_name'] as String,
              data['body'] as String?,
            ),
            if (system.isAndroid)
              TextSpan(text: '\n${currentAppLocalizations.updateVpnTip}'),
          ],
        ),
        confirmText:
            updateHostPlatform == 'windows' ||
                updateHostPlatform?.startsWith('android-') == true
            ? currentAppLocalizations.update
            : currentAppLocalizations.goDownload,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        await _applyUpdate(data);
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      await dialogs.showAlert(
        title: currentAppLocalizations.checkUpdate,
        message: TextSpan(text: currentAppLocalizations.checkUpdateError),
      );
    }
  }
}
