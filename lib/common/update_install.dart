import 'dart:io';

import 'package:fl_clash/common/linux_elevation.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/common/update_manifest.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:path/path.dart' as p;

enum UpdateInstallResult { started, needsPermission, failed }

/// Applies a verified installer. Desktop installs relaunch after this process
/// exits; the caller has to leave once this returns [UpdateInstallResult.started].
Future<UpdateInstallResult> installVerifiedUpdate(String path) async {
  try {
    if (Platform.isAndroid) return await _installAndroid(path);
    if (Platform.isWindows) return _installWindows(path);
    if (Platform.isMacOS) return await _installMacOS(path);
    if (Platform.isLinux) return await _installLinux(path);
  } catch (error) {
    commonPrint.log(
      'Installing the update failed: $error',
      logLevel: LogLevel.warning,
    );
  }
  return UpdateInstallResult.failed;
}

Future<UpdateInstallResult> _installAndroid(String path) async {
  final status = await app?.installApk(path);
  return switch (status) {
    'started' => UpdateInstallResult.started,
    'permission' => UpdateInstallResult.needsPermission,
    _ => UpdateInstallResult.failed,
  };
}

UpdateInstallResult _installWindows(String path) {
  final windowsHost = windows;
  if (windowsHost == null) return UpdateInstallResult.failed;
  final started = windowsHost.runas(
    path,
    windowsSilentInstallArguments,
    showWindow: false,
  );
  return started ? UpdateInstallResult.started : UpdateInstallResult.failed;
}

Future<UpdateInstallResult> _installMacOS(String path) async {
  final destination = macOSInstallDestination();
  if (destination == null) return UpdateInstallResult.failed;
  // A disk image and an admin-owned copy in /Applications are not writable.
  // Leaving the app running lets the user drag the opened image into place.
  if (!await macDestinationWritable(destination)) {
    await Process.run('open', [path]);
    return UpdateInstallResult.failed;
  }
  final staged = await _stageMacApp(path);
  await _spawnReplaceScript(macOSReplaceScript(), [staged, destination]);
  return UpdateInstallResult.started;
}

/// The parent directory has to accept a new bundle before this process exits.
Future<bool> macDestinationWritable(String destination) async {
  final parent = Directory(p.dirname(destination));
  if (!parent.existsSync()) return false;
  final probe = File(p.join(parent.path, '.nexo-update-probe-$pid'));
  try {
    await probe.writeAsString('ok');
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

Future<UpdateInstallResult> _installLinux(String path) async {
  final lower = path.toLowerCase();
  if (lower.endsWith('.appimage')) {
    final destination = Platform.environment['APPIMAGE'];
    if (destination == null || destination.isEmpty) {
      return UpdateInstallResult.failed;
    }
    await _spawnReplaceScript(linuxAppImageReplaceScript(), [
      path,
      destination,
    ]);
    return UpdateInstallResult.started;
  }
  final command = lower.endsWith('.deb')
      ? ['dpkg', '-i', path]
      : lower.endsWith('.rpm')
      ? ['rpm', '-U', path]
      : null;
  if (command == null) return UpdateInstallResult.failed;
  final installed = await linuxElevation.elevate(command);
  if (!installed) return UpdateInstallResult.failed;
  await _spawnReplaceScript(linuxRelaunchScript(), [
    Platform.resolvedExecutable,
  ]);
  return UpdateInstallResult.started;
}

/// Bundle to replace. A Gatekeeper translocation path is not the copy the
/// user launched, so the installed app in /Applications is the one updated.
String? macOSInstallDestination() {
  final executable = Platform.resolvedExecutable;
  final bundle = p.dirname(p.dirname(p.dirname(executable)));
  if (!bundle.endsWith('.app')) return null;
  if (bundle.contains('AppTranslocation')) {
    return '/Applications/${p.basename(bundle)}';
  }
  return bundle;
}

Future<String> _stageMacApp(String dmgPath) async {
  final mount = await Directory.systemTemp.createTemp('nexo-dmg-');
  final stage = await Directory.systemTemp.createTemp('nexo-app-');
  final attach = await Process.run('hdiutil', [
    'attach',
    dmgPath,
    '-nobrowse',
    '-readonly',
    '-mountpoint',
    mount.path,
  ]);
  if (attach.exitCode != 0) {
    throw ProcessException(
      'hdiutil',
      ['attach', dmgPath],
      attach.stderr.toString(),
      attach.exitCode,
    );
  }
  try {
    final apps = mount
        .listSync()
        .whereType<Directory>()
        .where((entry) => entry.path.endsWith('.app'))
        .toList();
    if (apps.isEmpty) {
      throw const FileSystemException('The disk image has no app');
    }
    final copy = await Process.run('cp', ['-R', apps.first.path, stage.path]);
    if (copy.exitCode != 0) {
      throw ProcessException(
        'cp',
        ['-R', apps.first.path],
        copy.stderr.toString(),
        copy.exitCode,
      );
    }
    return p.join(stage.path, p.basename(apps.first.path));
  } finally {
    await Process.run('hdiutil', ['detach', mount.path]);
  }
}

Future<void> _spawnReplaceScript(String script, List<String> arguments) async {
  final file = File(p.join(Directory.systemTemp.path, 'nexo-update-$pid.sh'));
  await file.writeAsString(script);
  await Process.run('chmod', ['+x', file.path]);
  await Process.start(file.path, [
    '$pid',
    ...arguments,
  ], mode: ProcessStartMode.detached);
}
