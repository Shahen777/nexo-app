import 'dart:ffi';
import 'dart:io';

const defaultUpdateMirror = 'https://nl.bingod.ru:9443';

const _sha256Pattern = r'^[0-9a-fA-F]{64}$';

/// A leading `v` and a `-pre` suffix compare as the same release. `+build` counts.
int compareReleaseVersion(String version1, String version2) {
  final left = _versionParts(version1);
  final right = _versionParts(version2);
  for (var index = 0; index < 3; index++) {
    final compared = left.numbers[index].compareTo(right.numbers[index]);
    if (compared != 0) return compared;
  }
  return left.build.compareTo(right.build);
}

class _VersionParts {
  const _VersionParts(this.numbers, this.build);

  final List<int> numbers;
  final int build;
}

_VersionParts _versionParts(String version) {
  var value = version.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  final plus = value.indexOf('+');
  final build = plus >= 0 ? int.parse(value.substring(plus + 1)) : 0;
  var core = plus >= 0 ? value.substring(0, plus) : value;
  final dash = core.indexOf('-');
  if (dash >= 0) core = core.substring(0, dash);
  final pieces = core.split('.');
  if (pieces.isEmpty || pieces.first.isEmpty) {
    throw FormatException('Not a version', version);
  }
  return _VersionParts([
    int.parse(pieces[0]),
    pieces.length > 1 ? int.parse(pieces[1]) : 0,
    pieces.length > 2 ? int.parse(pieces[2]) : 0,
  ], build);
}

String? normalizeMirrorBase(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  var path = uri.path;
  while (true) {
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
      continue;
    }
    const suffix = '/latest.json';
    if (path.endsWith(suffix)) {
      path = path.substring(0, path.length - suffix.length);
      continue;
    }
    break;
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

List<String> manifestCandidateUrls({
  required String? mirrorBase,
  required String repository,
}) {
  final urls = <String>[];
  final mirror = normalizeMirrorBase(mirrorBase);
  if (mirror != null) urls.add('$mirror/latest.json');
  urls.add(
    'https://github.com/$repository/releases/latest/download/latest.json',
  );
  return urls;
}

List<String> assetDownloadUrls({
  required String name,
  required String url,
  required String? mirrorBase,
  required String repository,
  required String tag,
}) {
  final safeName = releaseFileName(name);
  final urls = <String>[];
  final mirror = normalizeMirrorBase(mirrorBase);
  if (mirror != null && safeName != null) {
    urls.add('$mirror/${Uri.encodeComponent(safeName)}');
  }
  if (url.trim().isNotEmpty) urls.add(url.trim());
  if (safeName != null && tag.trim().isNotEmpty) {
    urls.add(
      'https://github.com/$repository/releases/download/${tag.trim()}/${Uri.encodeComponent(safeName)}',
    );
  }
  final seen = <String>{};
  return [
    for (final candidate in urls)
      if (seen.add(candidate)) candidate,
  ];
}

String? releaseFileName(String name) {
  if (name.contains('..')) return null;
  final base = name.split(RegExp(r'[/\\]')).last.trim();
  if (base.isEmpty || base == '.' || base == '..') return null;
  return base;
}

bool sha256Equals(String actual, String expected) {
  final left = actual.trim().toLowerCase();
  final right = expected.trim().toLowerCase();
  if (!RegExp(_sha256Pattern).hasMatch(left)) return false;
  if (!RegExp(_sha256Pattern).hasMatch(right)) return false;
  return left == right;
}

class ClassifiedRelease {
  const ClassifiedRelease({
    required this.platform,
    required this.arch,
    required this.kind,
  });

  final String platform;
  final String arch;
  final String kind;
}

ClassifiedRelease? classifyReleaseFile(String fileName) {
  final name = releaseFileName(fileName)?.toLowerCase();
  if (name == null) return null;
  if (name.endsWith('.apk')) {
    final arch = name.contains('arm64-v8a')
        ? 'arm64-v8a'
        : name.contains('armeabi-v7a')
        ? 'armeabi-v7a'
        : name.contains('x86_64')
        ? 'x86_64'
        : 'universal';
    return ClassifiedRelease(platform: 'android', arch: arch, kind: 'apk');
  }
  if (name.endsWith('.exe')) {
    return ClassifiedRelease(
      platform: 'windows',
      arch: _desktopArch(name),
      kind: 'exe',
    );
  }
  if (name.endsWith('.zip') && name.contains('windows')) {
    return ClassifiedRelease(
      platform: 'windows',
      arch: _desktopArch(name),
      kind: 'zip',
    );
  }
  if (name.endsWith('.dmg')) {
    return ClassifiedRelease(
      platform: 'macos',
      arch: name.contains('universal') ? 'universal' : _desktopArch(name),
      kind: 'dmg',
    );
  }
  if (name.endsWith('.appimage')) {
    return ClassifiedRelease(
      platform: 'linux',
      arch: _desktopArch(name),
      kind: 'appimage',
    );
  }
  if (name.endsWith('.deb')) {
    return ClassifiedRelease(
      platform: 'linux',
      arch: _desktopArch(name),
      kind: 'deb',
    );
  }
  if (name.endsWith('.rpm')) {
    return ClassifiedRelease(
      platform: 'linux',
      arch: _desktopArch(name),
      kind: 'rpm',
    );
  }
  return null;
}

String _desktopArch(String name) {
  if (name.contains('arm64') || name.contains('aarch64')) return 'arm64';
  return 'amd64';
}

class UpdateAsset {
  const UpdateAsset({
    required this.platform,
    required this.arch,
    required this.kind,
    required this.name,
    required this.sha256,
    required this.url,
    this.size,
  });

  final String platform;
  final String arch;
  final String kind;
  final String name;
  final String sha256;
  final String url;
  final int? size;
}

class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.tag,
    required this.notes,
    required this.assets,
  });

  final String version;
  final String tag;
  final String? notes;
  final List<UpdateAsset> assets;
}

class UpdateHost {
  const UpdateHost({required this.platform, required this.arch});

  final String platform;

  /// `arm64`, `arm`, or `amd64`. Android ABI names live on the asset.
  final String arch;
}

/// The package format this installation can apply.
UpdateHost currentUpdateHost() {
  return switch (Abi.current()) {
    Abi.androidArm64 => const UpdateHost(platform: 'android', arch: 'arm64'),
    Abi.androidArm => const UpdateHost(platform: 'android', arch: 'arm'),
    Abi.androidX64 => const UpdateHost(platform: 'android', arch: 'amd64'),
    Abi.windowsX64 => const UpdateHost(platform: 'windows', arch: 'amd64'),
    Abi.windowsArm64 => const UpdateHost(platform: 'windows', arch: 'arm64'),
    Abi.macosArm64 => const UpdateHost(platform: 'macos', arch: 'arm64'),
    Abi.macosX64 => const UpdateHost(platform: 'macos', arch: 'amd64'),
    Abi.linuxX64 => const UpdateHost(platform: 'linux', arch: 'amd64'),
    Abi.linuxArm64 => const UpdateHost(platform: 'linux', arch: 'arm64'),
    _ => UpdateHost(platform: Platform.operatingSystem, arch: 'amd64'),
  };
}

String preferredInstallKind(UpdateHost host, {required bool linuxAppImage}) {
  return switch (host.platform) {
    'linux' => linuxAppImage ? 'appimage' : 'deb',
    'windows' => 'exe',
    'android' => 'apk',
    'macos' => 'dmg',
    _ => '',
  };
}

UpdateManifest parseUpdateManifest(Map<String, dynamic> json) {
  final version = json['version'];
  if (version is! String || version.trim().isEmpty) {
    throw const FormatException('Update manifest has no version');
  }
  compareReleaseVersion(version, '0.0.0');
  final tag = json['tag'];
  final notes = json['notes'] ?? json['body'];
  final rawAssets = json['assets'];
  final assets = <UpdateAsset>[];
  if (rawAssets is List) {
    for (final entry in rawAssets) {
      if (entry is! Map) continue;
      final asset = _parseAsset(entry.cast<String, dynamic>());
      if (asset != null) assets.add(asset);
    }
  }
  return UpdateManifest(
    version: version.trim(),
    tag: tag is String && tag.trim().isNotEmpty ? tag.trim() : 'v$version',
    notes: notes is String ? notes : null,
    assets: assets,
  );
}

UpdateAsset? _parseAsset(Map<String, dynamic> json) {
  final platform = json['platform'];
  final arch = json['arch'];
  final kind = json['kind'];
  final name = json['name'];
  final sha256 = json['sha256'];
  final url = json['url'];
  if (platform is! String || arch is! String || name is! String) return null;
  if (sha256 is! String || !sha256Equals(sha256, sha256)) return null;
  final safeName = releaseFileName(name);
  if (safeName == null) return null;
  final resolvedKind = kind is String && kind.isNotEmpty
      ? kind
      : classifyReleaseFile(safeName)?.kind;
  if (resolvedKind == null) return null;
  final size = json['size'];
  return UpdateAsset(
    platform: platform,
    arch: arch,
    kind: resolvedKind,
    name: safeName,
    sha256: sha256.toLowerCase(),
    url: url is String ? url : '',
    size: size is int ? size : null,
  );
}

UpdateManifest? manifestFromGitHubRelease(Map<String, dynamic> release) {
  final tag = release['tag_name'];
  if (tag is! String || tag.trim().isEmpty) return null;
  final notes = release['body'];
  final version = tag.trim();
  try {
    compareReleaseVersion(version, '0.0.0');
  } on FormatException {
    return null;
  }
  return UpdateManifest(
    version: version,
    tag: version.startsWith('v') || version.startsWith('V')
        ? version
        : 'v$version',
    notes: notes is String ? notes : null,
    assets: const [],
  );
}

UpdateAsset? selectUpdateAsset(
  UpdateManifest manifest,
  UpdateHost host, {
  required String preferredKind,
}) {
  UpdateAsset? best;
  var bestScore = -1;
  for (final asset in manifest.assets) {
    if (asset.platform != host.platform) continue;
    final score = _assetScore(asset, host, preferredKind);
    if (score > bestScore) {
      best = asset;
      bestScore = score;
    }
  }
  return best;
}

int _assetScore(UpdateAsset asset, UpdateHost host, String preferredKind) {
  final archScore = switch (host.platform) {
    'android' => switch (host.arch) {
      'arm64' when asset.arch == 'arm64-v8a' => 100,
      'arm' when asset.arch == 'armeabi-v7a' => 100,
      'amd64' when asset.arch == 'x86_64' => 100,
      _ when asset.arch == 'universal' => 40,
      _ => -1,
    },
    _ when asset.arch == host.arch => 100,
    _ when asset.arch == 'universal' => 40,
    _ => -1,
  };
  if (archScore < 0) return -1;
  final kindBonus = asset.kind == preferredKind ? 20 : _kindRank(asset.kind);
  return archScore + kindBonus;
}

int _kindRank(String kind) {
  return switch (kind) {
    'apk' || 'exe' || 'dmg' || 'appimage' => 10,
    'deb' || 'zip' => 5,
    'rpm' => 1,
    _ => 0,
  };
}

Map<String, Object?> buildReleaseManifest({
  required String version,
  required String tag,
  required String repository,
  required String notes,
  required List<({String name, String sha256, int size})> files,
}) {
  final assets = <Map<String, Object?>>[];
  for (final file in files) {
    final classified = classifyReleaseFile(file.name);
    final safeName = releaseFileName(file.name);
    if (classified == null || safeName == null) continue;
    if (!sha256Equals(file.sha256, file.sha256)) continue;
    assets.add({
      'platform': classified.platform,
      'arch': classified.arch,
      'kind': classified.kind,
      'name': safeName,
      'sha256': file.sha256.toLowerCase(),
      'size': file.size,
      'url': 'https://github.com/$repository/releases/download/$tag/$safeName',
    });
  }
  return {
    'schema': 1,
    'version': version,
    'tag': tag,
    'notes': notes,
    'assets': assets,
  };
}

const windowsSilentInstallArguments =
    '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /RELAUNCH=1';

String macOSReplaceScript() {
  return '''
#!/bin/bash
set -euo pipefail
pid="\$1"
src="\$2"
dest="\$3"
while kill -0 "\$pid" 2>/dev/null; do
  sleep 0.2
done
rm -rf "\$dest"
mkdir -p "\$(dirname "\$dest")"
cp -R "\$src" "\$dest"
xattr -dr com.apple.quarantine "\$dest" || true
open "\$dest"
rm -rf "\$src"
rm -f "\$0"
''';
}

String linuxAppImageReplaceScript() {
  return '''
#!/bin/sh
set -eu
pid="\$1"
src="\$2"
dest="\$3"
while kill -0 "\$pid" 2>/dev/null; do
  sleep 0.2
done
cp -f "\$src" "\$dest"
chmod +x "\$dest"
"\$dest" >/dev/null 2>&1 &
rm -f "\$src"
rm -f "\$0"
''';
}

String linuxRelaunchScript() {
  return '''
#!/bin/sh
set -eu
pid="\$1"
exe="\$2"
while kill -0 "\$pid" 2>/dev/null; do
  sleep 0.2
done
"\$exe" >/dev/null 2>&1 &
rm -f "\$0"
''';
}
