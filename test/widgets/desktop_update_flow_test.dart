import 'dart:async';

import 'package:fl_clash/common/desktop_updater.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

class _MacUpdater extends DesktopUpdater {
  final checks = <bool>[];

  @override
  Future<bool> checkForUpdates({
    required String manifestUrl,
    required bool background,
    required bool safeMode,
  }) async {
    checks.add(background);
    return true;
  }
}

class _MacUpdateAction extends CommonAction {
  _MacUpdateAction(this.updater);

  final DesktopUpdater updater;

  @override
  String? get updateHostPlatform => 'macos';

  @override
  DesktopUpdater get desktopUpdater => updater;
}

class _WindowsUpdateAction extends CommonAction {
  _WindowsUpdateAction(this.started);

  final bool? started;
  int installs = 0;

  @override
  String? get updateHostPlatform => 'windows';

  @override
  Future<bool?> downloadAndInstallUpdate(
    Map<String, dynamic> release, {
    required String? platform,
  }) async {
    installs++;
    return started;
  }
}

class _ControlledUpdateAction extends CommonAction {
  final manifests = <Future<Map<String, dynamic>?> Function()>[];
  Future<void> Function()? clear;
  Future<bool?> Function()? install;
  int clears = 0;
  int fetches = 0;
  int installs = 0;

  @override
  String? get updateHostPlatform => 'windows';

  @override
  Future<void> clearDownloadedUpdate() async {
    clears++;
    await clear?.call();
  }

  @override
  Future<Map<String, dynamic>?> fetchUpdateRelease() {
    fetches++;
    return manifests.removeAt(0)();
  }

  @override
  Future<bool?> downloadAndInstallUpdate(
    Map<String, dynamic> release, {
    required String? platform,
  }) async {
    installs++;
    return await install?.call();
  }
}

class _RecordingSystemAction extends SystemAction {
  int exits = 0;

  @override
  Future<void> handleExit([bool needSave = true]) async {
    exits++;
  }
}

void main() {
  Future<ProviderContainer> pumpApp(
    WidgetTester tester,
    CommonAction action, {
    bool safeMode = false,
    SystemAction? systemAction,
  }) async {
    final container = ProviderContainer(
      overrides: [
        commonActionProvider.overrideWith(() => action),
        safeModeProvider.overrideWithValue(safeMode),
        if (systemAction != null)
          systemActionProvider.overrideWith(() => systemAction),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.listen(appSettingProvider, (_, _) {});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: Scaffold(body: SizedBox.shrink())),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('macOS manual and automatic checks go directly to Sparkle', (
    tester,
  ) async {
    final updater = _MacUpdater();
    final action = _MacUpdateAction(updater);
    final container = await pumpApp(tester, action);
    final notifier = container.read(commonActionProvider.notifier);

    await notifier.checkUpdate();
    await tester.pump(const Duration(seconds: 1));
    expect(updater.checks, [false]);
    expect(find.byType(AlertDialog), findsNothing);

    expect(await notifier.autoCheckUpdate(), isTrue);
    expect(updater.checks, [false, true]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS automatic checks respect the reminder setting', (
    tester,
  ) async {
    final updater = _MacUpdater();
    final action = _MacUpdateAction(updater);
    final container = await pumpApp(tester, action);
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoCheckUpdate: false));

    expect(
      await container.read(commonActionProvider.notifier).autoCheckUpdate(),
      isFalse,
    );
    expect(updater.checks, isEmpty);
  });

  testWidgets(
    'safe mode blocks both manual and automatic native update checks',
    (tester) async {
      final updater = _MacUpdater();
      final action = _MacUpdateAction(updater);
      final container = await pumpApp(tester, action, safeMode: true);
      final notifier = container.read(commonActionProvider.notifier);

      await notifier.checkUpdate();
      expect(await notifier.autoCheckUpdate(), isFalse);
      expect(updater.checks, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  for (final started in [true, false, null]) {
    testWidgets(
      'Windows exits through SystemAction only after installer result $started',
      (tester) async {
        final action = _WindowsUpdateAction(started);
        final systemAction = _RecordingSystemAction();
        final container = await pumpApp(
          tester,
          action,
          systemAction: systemAction,
        );
        final shown = container
            .read(commonActionProvider.notifier)
            .checkUpdateResultHandle(
              data: {'tag_name': 'v0.9.7', 'body': '- In-app updates'},
              isUser: true,
            );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Update'));
        await tester.pumpAndSettle();

        expect(action.installs, 1);
        expect(systemAction.exits, started == true ? 1 : 0);
        if (started == false) {
          expect(find.text('Check for updates'), findsOneWidget);
          await tester.tap(find.byType(TextButton).first);
          await tester.pumpAndSettle();
        }
        await shown;
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('automatic cleanup and manifest fetch exclude a manual check', (
    tester,
  ) async {
    final action = _ControlledUpdateAction();
    final cleared = Completer<void>();
    final manifest = Completer<Map<String, dynamic>?>();
    action.clear = () => cleared.future;
    action.manifests.add(() => manifest.future);
    final container = await pumpApp(tester, action);
    final notifier = container.read(commonActionProvider.notifier);

    final automatic = notifier.autoCheckUpdate();
    await tester.pump();
    expect(action.clears, 1);
    expect(action.fetches, 0);
    await notifier.checkUpdate();
    expect(action.fetches, 0);
    expect(find.byType(CommonDialog), findsNothing);

    cleared.complete();
    await tester.pump();
    expect(action.fetches, 1);
    await notifier.checkUpdate();
    expect(action.fetches, 1);

    manifest.complete({'tag_name': 'v0.9.7', 'body': '- Updates'});
    await tester.pumpAndSettle();
    expect(find.byType(CommonDialog), findsOneWidget);
    await notifier.checkUpdate();
    expect(find.byType(CommonDialog), findsOneWidget);
    expect(action.fetches, 1);
    expect(action.installs, 0);

    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();
    expect(await automatic, isTrue);

    final retryManifest = Completer<Map<String, dynamic>?>();
    action.manifests.add(() => retryManifest.future);
    final retry = notifier.checkUpdate();
    await tester.pump();
    expect(action.fetches, 2);
    retryManifest.complete({'tag_name': 'v0.9.7', 'body': '- Updates'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();
    await retry;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual update ownership lasts through confirmation and installer handoff',
    (tester) async {
      final action = _ControlledUpdateAction();
      final manifest = Completer<Map<String, dynamic>?>();
      final installer = Completer<bool?>();
      action.manifests.add(() => manifest.future);
      action.install = () => installer.future;
      final container = await pumpApp(tester, action);
      final notifier = container.read(commonActionProvider.notifier);

      final manual = notifier.checkUpdate();
      await tester.pump();
      expect(await notifier.autoCheckUpdate(), isFalse);
      expect(action.clears, 0);
      expect(action.fetches, 1);

      manifest.complete({'tag_name': 'v0.9.7', 'body': '- Updates'});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(CommonDialog), findsOneWidget);
      expect(await notifier.autoCheckUpdate(), isFalse);
      expect(action.clears, 0);
      expect(action.fetches, 1);

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(action.installs, 1);
      expect(await notifier.autoCheckUpdate(), isFalse);
      expect(action.clears, 0);
      expect(action.fetches, 1);

      installer.complete(null);
      await tester.pump();
      await manual;

      action.manifests.add(() async => null);
      expect(await notifier.autoCheckUpdate(), isFalse);
      expect(action.clears, 1);
      expect(action.fetches, 2);
      expect(action.installs, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failsDuringCleanup in [true, false]) {
    testWidgets(
      'an update error during ${failsDuringCleanup ? 'cleanup' : 'manifest fetch'} releases operation ownership',
      (tester) async {
        final action = _ControlledUpdateAction();
        if (failsDuringCleanup) {
          action.clear = () async => throw StateError('cleanup failed');
        } else {
          action.manifests.add(() async => throw StateError('manifest failed'));
        }
        final container = await pumpApp(tester, action);
        final notifier = container.read(commonActionProvider.notifier);

        expect(await notifier.autoCheckUpdate(), isFalse);
        action.clear = null;
        action.manifests.add(() async => null);

        expect(await notifier.autoCheckUpdate(), isFalse);
        expect(action.clears, 2);
        expect(action.fetches, failsDuringCleanup ? 1 : 2);
        expect(action.installs, 0);
        expect(find.byType(CommonDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
