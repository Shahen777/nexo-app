import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../helpers/app_paths.dart';

class _InstallerAdapter implements HttpClientAdapter {
  _InstallerAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions, Future<void>?) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options, cancelFuture);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  late Dio client;
  late Request request;
  final bytes = utf8.encode('verified installer fixture');

  Map<String, dynamic> release({String? checksum, String? url}) => {
    'url': url ?? 'https://updates.test/download/Nexo.exe',
    'sha256': checksum ?? sha256.convert(bytes).toString(),
  };

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('nexo-update-test-');
    await useAppPaths(cache);
    client = Dio();
    client.httpClientAdapter = _InstallerAdapter((_, _) async {
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {Headers.contentLengthHeader: ['${bytes.length}']},
      );
    });
    request = Request(downloadClient: client);
  });

  tearDown(() async {
    client.close(force: true);
    await cache.delete(recursive: true);
  });

  for (final (platform, fileName) in [
    ('windows', 'Nexo.exe'),
    ('android-arm64', 'Nexo.apk'),
    ('android-arm', 'Nexo.apk'),
  ]) {
    test('a verified $platform download keeps the matching installer extension', () async {
      final installer = await request.downloadUpdate(
        release(),
        platform: platform,
        cancelToken: CancelToken(),
        onProgress: (_) {},
      );
      expect(installer, path.join(cache.path, 'update', fileName));
      expect(await File(installer).readAsBytes(), bytes);
    });
  }

  test('a checksum mismatch removes the downloaded executable', () async {
    await expectLater(
      request.downloadUpdate(
        release(checksum: '0' * 64),
        platform: 'windows',
        cancelToken: CancelToken(),
        onProgress: (_) {},
      ),
      throwsFormatException,
    );
    expect(await File(path.join(cache.path, 'update', 'Nexo.exe')).exists(), isFalse);
  });

  test('cancelled downloads never leave an installer available to launch', () async {
    final entered = Completer<void>();
    client.httpClientAdapter = _InstallerAdapter((options, cancelled) async {
      entered.complete();
      await cancelled;
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'test cancellation',
      );
    });
    final token = CancelToken();
    final pending = request.downloadUpdate(
      release(),
      platform: 'windows',
      cancelToken: token,
      onProgress: (_) {},
    );
    final outcome = expectLater(
      pending,
      throwsA(isA<DioException>().having((error) => error.type, 'type', DioExceptionType.cancel)),
    );
    await entered.future;
    token.cancel();
    await outcome;
    expect(await File(path.join(cache.path, 'update', 'Nexo.exe')).exists(), isFalse);
  });

  test('invalid installer URLs and unsupported platforms never download', () async {
    var fetched = false;
    client.httpClientAdapter = _InstallerAdapter((_, _) async {
      fetched = true;
      throw StateError('unexpected fetch');
    });
    for (final url in ['http://updates.test/Nexo.exe', 'https://u:p@updates.test/Nexo.exe']) {
      await expectLater(
        request.downloadUpdate(
          release(url: url),
          platform: 'windows',
          cancelToken: CancelToken(),
          onProgress: (_) {},
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      request.downloadUpdate(
        release(),
        platform: 'macos',
        cancelToken: CancelToken(),
        onProgress: (_) {},
      ),
      throwsUnsupportedError,
    );
    expect(fetched, isFalse);
  });
}
