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
    'cancelling disposes the download and prevents late installation',
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
      await tester.pumpAndSettle();
      expect(await result.future, isNull);
      expect(token.isCancelled, isTrue);

      downloaded.complete(r'C:\cache\Nexo.exe');
      await tester.pump();

      expect(installed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

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
