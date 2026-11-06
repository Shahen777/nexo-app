import 'package:fl_clash/common/desktop_updater.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nexo/updater');
  const manifest = 'https://updates.test:8444/nexo/update.json';
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'macOS manual and background checks use the adjacent HTTPS appcast',
    () async {
      const updater = DesktopUpdater();
      for (final background in [false, true]) {
        expect(
          await updater.checkForUpdates(
            manifestUrl: manifest,
            background: background,
            safeMode: false,
          ),
          isTrue,
        );
      }
      expect(calls.map((call) => call.method), [
        'checkForUpdates',
        'checkForUpdatesInBackground',
      ]);
      expect(
        calls.map((call) => call.arguments),
        everyElement({'feedUrl': 'https://updates.test:8444/nexo/appcast.xml'}),
      );
    },
  );

  test('safe mode never invokes the native updater', () async {
    expect(
      await const DesktopUpdater().checkForUpdates(
        manifestUrl: manifest,
        background: false,
        safeMode: true,
      ),
      isFalse,
    );
    expect(calls, isEmpty);
  });

  test(
    'an invalid or unconfigured appcast never reaches the native updater',
    () async {
      for (final url in [
        '',
        'http://updates.test/update.json',
        'https://u:p@updates.test/update.json',
      ]) {
        await expectLater(
          const DesktopUpdater().checkForUpdates(
            manifestUrl: url,
            background: false,
            safeMode: false,
          ),
          throwsStateError,
        );
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'native update failures propagate to the manual error handler',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'updater_start_failed');
          });
      await expectLater(
        const DesktopUpdater().checkForUpdates(
          manifestUrl: manifest,
          background: false,
          safeMode: false,
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test(
    'Windows opens the verified local executable through the OS launcher',
    () async {
      final launched = <Uri>[];
      final started = await launchUpdateInstaller(
        r'C:\Users\Test User\cache\update\Nexo.exe',
        platform: 'windows',
        installAndroid: (_) async => throw StateError('wrong installer'),
        launchWindows: (file) async {
          launched.add(file);
          return true;
        },
      );
      expect(started, isTrue);
      expect(launched.single.scheme, 'file');
      expect(
        launched.single.toFilePath(windows: true),
        r'C:\Users\Test User\cache\update\Nexo.exe',
      );
    },
  );

  test('Android keeps the platform package-installer path', () async {
    String? installed;
    expect(
      await launchUpdateInstaller(
        '/cache/update/Nexo.apk',
        platform: 'android-arm64',
        installAndroid: (path) async {
          installed = path;
          return true;
        },
        launchWindows: (_) async => throw StateError('wrong installer'),
      ),
      isTrue,
    );
    expect(installed, '/cache/update/Nexo.apk');
  });

  test(
    'installer refusal and launch errors are not reported as success',
    () async {
      Future<bool> start(Future<bool> Function(Uri) launcher) =>
          launchUpdateInstaller(
            r'C:\cache\Nexo.exe',
            platform: 'windows',
            installAndroid: (_) async => false,
            launchWindows: launcher,
          );
      expect(await start((_) async => false), isFalse);
      await expectLater(
        start((_) async => throw PlatformException(code: 'launch_failed')),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('unsupported platforms and non-installer paths never launch', () async {
    var launched = false;
    for (final (platform, file) in [
      ('windows', r'C:\cache\payload.txt'),
      ('windows', r'Nexo.exe'),
      ('android-arm64', '/cache/payload.exe'),
      ('macos', '/cache/Nexo.dmg'),
    ]) {
      await expectLater(
        launchUpdateInstaller(
          file,
          platform: platform,
          installAndroid: (_) async => launched = true,
          launchWindows: (_) async => launched = true,
        ),
        throwsA(anyOf(isA<ArgumentError>(), isA<UnsupportedError>())),
      );
    }
    expect(launched, isFalse);
  });
}
