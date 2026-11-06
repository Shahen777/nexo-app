import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' show join;

class Request {
  late final Dio dio;
  late final Dio _clashDio;
  String? userAgent;

  ProviderReader? _read;

  void attach(ProviderReader read) {
    _read = read;
  }

  Request({Dio? downloadClient}) {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    _clashDio = downloadClient ?? Dio();
    if (downloadClient != null) return;
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = globalState.ua;
          final read = _read;
          if (read == null) {
            return 'DIRECT';
          }
          return FlClashHttpOverrides.findProxyForReader(read, uri);
        };
        return client;
      },
    );
  }

  Future<Response<T>> _download<T>(String url, ResponseType responseType) {
    final target = downloadTarget(url);
    final cancelToken = CancelToken();
    return _clashDio
        .getUri<T>(
          target.uri,
          options: Options(responseType: responseType, headers: target.headers),
          cancelToken: cancelToken,
        )
        .timeout(
          downloadTimeoutDuration,
          onTimeout: () {
            cancelToken.cancel();
            throw DioException.receiveTimeout(
              timeout: downloadTimeoutDuration,
              requestOptions: RequestOptions(path: url),
            );
          },
        );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      return await _download<Uint8List>(url, ResponseType.bytes);
    } catch (e) {
      commonPrint.log(
        'getFileResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    try {
      return await _download<String>(url, ResponseType.plain);
    } catch (e) {
      commonPrint.log(
        'getTextResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  /// Null when this build is current or nothing is published for this device;
  /// throws when the update server cannot be asked.
  Future<Map<String, dynamic>?> checkForUpdate() async {
    if (updateManifestUrl.isEmpty) return null;
    final response = await getTextResponseForUrl(updateManifestUrl);
    return newerRelease(
      jsonDecode(response.data!) as Map<String, dynamic>,
      platform: updatePlatform,
      currentVersion: globalState.packageInfo.version,
      manifestUrl: updateManifestUrl,
    );
  }

  Future<String> _updateFilePath(String? platform) async {
    final fileName = updateInstallerFileName(platform);
    final cacheDir = await appPath.cacheDir.future;
    return join(cacheDir.path, 'update', fileName);
  }

  /// Returns the installer's path once its checksum matches the release's.
  Future<String> downloadUpdate(
    Map<String, dynamic> release, {
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
    String? platform,
  }) async {
    final url = Uri.parse(release['url'] as String);
    final expectedHash = release['sha256'] as String;
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedHash)) {
      throw const FormatException('Invalid installer URL or checksum');
    }
    final path = await _updateFilePath(platform ?? updatePlatform);
    final file = File(path);
    try {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      await file.parent.create(recursive: true);
      await _clashDio.download(
        url.toString(),
        path,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: false,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
      );
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != expectedHash.toLowerCase()) {
        throw const FormatException('The installer checksum does not match');
      }
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      return path;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  /// An installed update leaves its installer behind in the cache.
  Future<void> removeDownloadedUpdate() async {
    final cacheDir = await appPath.cacheDir.future;
    for (final name in ['Nexo.apk', 'Nexo.exe']) {
      final file = File(join(cacheDir.path, 'update', name));
      if (await file.exists()) await file.delete();
    }
  }
}

/// The renewal page of a subscription served by the Nexo site; null for any
/// other subscription, whose token that site would not know.
Uri? nexoRenewUrl(String subscriptionUrl, {String site = updateManifestUrl}) {
  final siteUri = Uri.tryParse(site);
  final subscription = Uri.tryParse(subscriptionUrl);
  if (siteUri == null || subscription == null || site.isEmpty) return null;
  final segments = subscription.pathSegments;
  final sameSite =
      subscription.scheme == siteUri.scheme &&
      subscription.host == siteUri.host &&
      subscription.port == siteUri.port;
  if (!sameSite || segments.length < 2) return null;
  if (segments[segments.length - 2] != 'sub') return null;
  return siteUri.resolve('/renew/${segments.last}');
}

String updateInstallerFileName(String? platform) => switch (platform) {
  'android-arm64' || 'android-arm' => 'Nexo.apk',
  'windows' => 'Nexo.exe',
  _ => throw UnsupportedError('No downloadable installer for $platform'),
};

/// The manifest key of the installer this device can run.
String? get updatePlatform => switch (Abi.current()) {
  Abi.androidArm64 => 'android-arm64',
  Abi.androidArm => 'android-arm',
  Abi.windowsX64 => 'windows',
  Abi.macosArm64 || Abi.macosX64 => 'macos',
  _ => null,
};

@visibleForTesting
Map<String, dynamic>? newerRelease(
  Map<String, dynamic> manifest, {
  required String? platform,
  required String currentVersion,
  required String manifestUrl,
}) {
  final entry = manifest[platform];
  if (entry is! Map<String, dynamic>) return null;
  final version = entry['version'] as String;
  if (compareVersions(version, currentVersion) <= 0) return null;
  return {
    'tag_name': 'v$version',
    'body': entry['body'] as String?,
    'url': Uri.parse(manifestUrl).resolve(entry['file'] as String).toString(),
    'sha256': entry['sha256'] as String,
  };
}

final request = Request();

/// Some subscription servers send a gzip or zlib body without saying so in
/// Content-Encoding, which is the only signal dart:io decompresses on.
Uint8List decompressUnlabeled(Uint8List bytes) {
  final codec = switch (bytes) {
    [0x1f, 0x8b, ...] => gzip,
    [0x78, final flags, ...] when (0x78 << 8 | flags) % 31 == 0 => zlib,
    _ => null,
  };
  if (codec == null) {
    return bytes;
  }
  try {
    return Uint8List.fromList(codec.decode(bytes));
  } on FormatException {
    return bytes;
  }
}

/// dart:io turns [Uri.userInfo] into Basic credentials still percent-encoded.
@visibleForTesting
({Uri uri, Map<String, Object> headers}) downloadTarget(String url) {
  final uri = url.webUri ?? Uri.parse(url);
  if (uri.userInfo.isEmpty) {
    return (uri: uri, headers: const {});
  }
  final credentials = uri.userInfo.split(':').map(_decodeUserInfo).join(':');
  return (
    uri: uri.replace(userInfo: ''),
    headers: {
      HttpHeaders.authorizationHeader:
          'Basic ${base64.encode(utf8.encode(credentials))}',
    },
  );
}

String _decodeUserInfo(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

String? getFileNameForDisposition(String? disposition) {
  if (disposition == null) return null;
  final parseValue = HeaderValue.parse(disposition);
  final parameters = parseValue.parameters;
  final fileNamePointKey = parameters.keys.firstWhere(
    (key) => key == 'filename*',
    orElse: () => '',
  );
  if (fileNamePointKey.isNotEmpty) {
    final res = parameters[fileNamePointKey]?.split("''") ?? [];
    if (res.length >= 2) {
      return Uri.decodeComponent(res[1]);
    }
  }
  final fileNameKey = parameters.keys.firstWhere(
    (key) => key == 'filename',
    orElse: () => '',
  );
  if (fileNameKey.isEmpty) return null;
  return parameters[fileNameKey];
}
