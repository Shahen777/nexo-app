import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

Uri? macosAppcastUri(String manifestUrl) {
  final manifest = Uri.tryParse(manifestUrl);
  if (manifest == null ||
      manifest.scheme != 'https' ||
      manifest.host.isEmpty ||
      manifest.userInfo.isNotEmpty ||
      manifest.hasFragment) {
    return null;
  }
  return manifest.resolve('appcast.xml');
}

class DesktopUpdater {
  const DesktopUpdater({
    this.channel = const MethodChannel('nexo/updater'),
  });

  final MethodChannel channel;

  Future<bool> checkForUpdates({
    required String manifestUrl,
    required bool background,
    required bool safeMode,
  }) async {
    if (safeMode) return false;
    final feed = macosAppcastUri(manifestUrl);
    if (feed == null) {
      throw StateError('The update feed is not configured');
    }
    return await channel.invokeMethod<bool>(
          background ? 'checkForUpdatesInBackground' : 'checkForUpdates',
          {'feedUrl': feed.toString()},
        ) ??
        false;
  }
}

Future<bool> _launchWindowsInstaller(Uri file) =>
    launchUrl(file, mode: LaunchMode.externalApplication);

Future<bool> launchUpdateInstaller(
  String installerPath, {
  required String? platform,
  required Future<bool> Function(String path) installAndroid,
  Future<bool> Function(Uri file) launchWindows = _launchWindowsInstaller,
}) async {
  switch (platform) {
    case 'android-arm64' || 'android-arm':
      if (!path.posix.isAbsolute(installerPath) ||
          path.posix.extension(installerPath).toLowerCase() != '.apk') {
        throw ArgumentError.value(installerPath, 'installerPath');
      }
      return installAndroid(installerPath);
    case 'windows':
      final windowsPath = path.Context(style: path.Style.windows);
      if (!windowsPath.isAbsolute(installerPath) ||
          windowsPath.extension(installerPath).toLowerCase() != '.exe') {
        throw ArgumentError.value(installerPath, 'installerPath');
      }
      return launchWindows(Uri.file(installerPath, windows: true));
    default:
      throw UnsupportedError('No in-app installer for $platform');
  }
}
