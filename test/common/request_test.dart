import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/request.dart';
import 'package:flutter_test/flutter_test.dart';

class _StalledHttpClient extends Fake implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  String Function(Uri url)? findProxy;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getTextResponseForUrl propagates the typed DioException', () async {
    // flutter_test's mocked HttpClient answers every request with HTTP 400,
    // which Dio surfaces as a badResponse DioException.
    await expectLater(
      request.getTextResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  test('getFileResponseForUrl propagates the typed DioException', () async {
    await expectLater(
      request.getFileResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  group('newerRelease', () {
    const manifestUrl = 'https://updates.test:8444/nexo/update.json';
    const manifest = <String, dynamic>{
      'android-arm64': {
        'version': '1.2.4',
        'file': 'download/Nexo-android.apk',
        'sha256': 'abc',
        'body': '- Notes',
      },
    };

    test('describes a newer installer for this device', () {
      expect(
        newerRelease(
          manifest,
          platform: 'android-arm64',
          currentVersion: '1.2.3',
          manifestUrl: manifestUrl,
        ),
        {
          'tag_name': 'v1.2.4',
          'body': '- Notes',
          'url': 'https://updates.test:8444/nexo/download/Nexo-android.apk',
          'sha256': 'abc',
        },
      );
    });

    test('is empty when the build is current', () {
      expect(
        newerRelease(
          manifest,
          platform: 'android-arm64',
          currentVersion: '1.2.4',
          manifestUrl: manifestUrl,
        ),
        isNull,
      );
    });

    test('is empty when nothing is published for this device', () {
      expect(
        newerRelease(
          manifest,
          platform: 'android-arm',
          currentVersion: '1.2.3',
          manifestUrl: manifestUrl,
        ),
        isNull,
      );
      expect(
        newerRelease(
          manifest,
          platform: null,
          currentVersion: '1.2.3',
          manifestUrl: manifestUrl,
        ),
        isNull,
      );
    });
  });

  group('nexoRenewUrl', () {
    const site = 'https://updates.test:8444/nexo/update.json';

    test('opens the renewal page of a subscription from the site', () {
      expect(
        nexoRenewUrl(
          'https://updates.test:8444/nexo/sub/token123',
          site: site,
        ).toString(),
        'https://updates.test:8444/renew/token123',
      );
    });

    test('offers nothing for another provider or an unset site', () {
      expect(
        nexoRenewUrl('https://other.test:8444/nexo/sub/token123', site: site),
        isNull,
      );
      expect(
        nexoRenewUrl('https://updates.test:8444/nexo/sub/t', site: ''),
        isNull,
      );
      expect(nexoRenewUrl('https://updates.test:8444/app', site: site), isNull);
    });
  });

  group('downloadTarget', () {
    test('sends a URL without credentials unchanged', () {
      final target = downloadTarget('https://example.com/a.yaml?x=1');

      expect(target.uri.toString(), 'https://example.com/a.yaml?x=1');
      expect(target.headers, isEmpty);
    });

    test('moves decoded credentials into the Authorization header', () {
      for (final url in [
        'https://me@mail.com:p:w@dav.example.com/dav/a.yaml',
        'https://me%40mail.com:p%3Aw@dav.example.com/dav/a.yaml',
      ]) {
        final target = downloadTarget(url);

        expect(target.uri.toString(), 'https://dav.example.com/dav/a.yaml');
        expect(
          target.headers[HttpHeaders.authorizationHeader],
          'Basic ${base64.encode(utf8.encode('me@mail.com:p:w'))}',
        );
      }
    });
  });

  group('decompressUnlabeled', () {
    final yaml = utf8.encode('proxies: []\n');

    test('inflates a gzip or zlib body that arrived unlabeled', () {
      for (final codec in [gzip, zlib]) {
        final body = Uint8List.fromList(codec.encode(yaml));

        expect(decompressUnlabeled(body), yaml);
      }
    });

    test('leaves a plain body untouched', () {
      final body = Uint8List.fromList(yaml);

      expect(decompressUnlabeled(body), same(body));
    });

    test('keeps a body that only starts like gzip', () {
      final body = Uint8List.fromList([0x1f, 0x8b, 1, 2, 3]);

      expect(decompressUnlabeled(body), same(body));
    });
  });

  testWidgets('a stalled download fails at the shared download deadline', (
    tester,
  ) async {
    late final Future<Response<String>> pending;
    HttpOverrides.runZoned(() {
      pending = Request().getTextResponseForUrl('http://127.0.0.1/stalled');
    }, createHttpClient: (_) => _StalledHttpClient());
    var settled = false;
    final outcome = expectLater(
      pending.whenComplete(() => settled = true),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );

    await tester.pump(downloadTimeoutDuration - const Duration(seconds: 1));
    expect(settled, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await outcome;
  });
}
