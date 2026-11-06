import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/update_download_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  Future<Completer<bool?>> open(
    WidgetTester tester,
    UpdateDownloadDialog dialog, {
    bool safeMode = false,
  }) async {
    final result = Completer<bool?>();
    final container = ProviderContainer(
      overrides: [safeModeProvider.overrideWithValue(safeMode)],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showFloatingDialog<bool>(
                  context: context,
                  child: dialog,
                  dismissible: false,
                ).then(result.complete);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    return result;
  }

  testWidgets(
    'a completed download opens the installer and closes successfully',
    (tester) async {
      final downloaded = Completer<String>();
      final installed = <String>[];
      final result = await open(
        tester,
        UpdateDownloadDialog(
          release: const {},
          platform: 'windows',
          download: (_, {required cancelToken, required onProgress, platform}) {
            expect(platform, 'windows');
            onProgress(0.5);
            return downloaded.future;
          },
          install: (path) async {
            installed.add(path);
            return true;
          },
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.5,
      );

      downloaded.complete(r'C:\cache\Nexo.exe');
      await tester.pumpAndSettle();

      expect(await result.future, isTrue);
      expect(installed, [r'C:\cache\Nexo.exe']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'installer handoff disables Cancel and Back until the launcher completes',
    (tester) async {
      final downloaded = Completer<String>();
      final installer = Completer<bool>();
      late CancelToken token;
      var installCalls = 0;
      final result = await open(
        tester,
        UpdateDownloadDialog(
          release: const {},
          platform: 'windows',
          download: (_, {required cancelToken, required onProgress, platform}) {
            token = cancelToken;
            onProgress(1);
            return downloaded.future;
          },
          install: (_) {
            installCalls++;
            return installer.future;
          },
        ),
      );

      downloaded.complete(r'C:\cache\Nexo.exe');
      await tester.pump();
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(installCalls, 1);
      expect(tester.widget<TextButton>(cancel).onPressed, isNull);
      await tester.tap(cancel);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(result.isCompleted, isFalse);
      expect(token.isCancelled, isFalse);
      expect(find.byType(UpdateDownloadDialog), findsOneWidget);

      installer.complete(true);
      await tester.pumpAndSettle();

      expect(await result.future, isTrue);
      expect(find.byType(UpdateDownloadDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a failed download never invokes the installer', (tester) async {
    var installed = false;
    final result = await open(
      tester,
      UpdateDownloadDialog(
        release: const {},
        download:
            (_, {required cancelToken, required onProgress, platform}) async {
              throw const FormatException('checksum mismatch');
            },
        install: (_) async => installed = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(await result.future, isFalse);
    expect(installed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Cancel prevents installation when the download finishes before the dismissal animation',
    (tester) async {
      final downloaded = Completer<String>();
      late CancelToken token;
      var installed = false;
      final result = await open(
        tester,
        UpdateDownloadDialog(
          release: const {},
          download: (_, {required cancelToken, required onProgress, platform}) {
            token = cancelToken;
            return downloaded.future;
          },
          install: (_) async => installed = true,
        ),
      );
      await tester.tap(find.text('Cancel'));
      expect(token.isCancelled, isTrue);
      expect(result.isCompleted, isFalse);
      downloaded.complete(r'C:\cache\Nexo.exe');
      await tester.pumpAndSettle();

      expect(await result.future, isNull);
      expect(installed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final cancelWithBack in [false, true]) {
    testWidgets(
      '${cancelWithBack ? 'Back' : 'Cancel'} keeps operation ownership until cancelled-download cleanup finishes',
      (tester) async {
        final cleaned = Completer<void>();
        late CancelToken token;
        var installed = false;
        final result = await open(
          tester,
          UpdateDownloadDialog(
            release: const {},
            download:
                (
                  _, {
                  required cancelToken,
                  required onProgress,
                  platform,
                }) async {
                  token = cancelToken;
                  final cancelled = await token.whenCancel;
                  await cleaned.future;
                  throw cancelled;
                },
            install: (_) async => installed = true,
          ),
        );

        if (cancelWithBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text('Cancel'));
        }
        expect(token.isCancelled, isTrue);
        await tester.pump();
        expect(result.isCompleted, isFalse);
        expect(find.byType(UpdateDownloadDialog), findsOneWidget);
        expect(installed, isFalse);

        cleaned.complete();
        await tester.pumpAndSettle();

        expect(await result.future, isNull);
        expect(find.byType(UpdateDownloadDialog), findsNothing);
        expect(find.text('open'), findsOneWidget);
        expect(installed, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('safe mode starts neither a download nor an installer', (
    tester,
  ) async {
    var effects = 0;
    final result = await open(
      tester,
      UpdateDownloadDialog(
        release: const {},
        download:
            (_, {required cancelToken, required onProgress, platform}) async {
              effects++;
              return r'C:\cache\Nexo.exe';
            },
        install: (_) async {
          effects++;
          return true;
        },
      ),
      safeMode: true,
    );
    await tester.pumpAndSettle();

    expect(await result.future, isFalse);
    expect(effects, 0);
    expect(tester.takeException(), isNull);
  });
}
