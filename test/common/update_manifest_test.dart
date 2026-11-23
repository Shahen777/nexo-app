import 'dart:io';

import 'package:fl_clash/common/update_install.dart';
import 'package:fl_clash/common/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  group('compareReleaseVersion', () {
    test('orders major, minor, patch, and build', () {
      expect(compareReleaseVersion('1.0.0', '1.0.0'), 0);
      expect(compareReleaseVersion('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareReleaseVersion('1.2.0', '1.1.9'), greaterThan(0));
      expect(compareReleaseVersion('1.0.2', '1.0.1'), greaterThan(0));
      expect(compareReleaseVersion('1.0.0+1', '1.0.0+2'), lessThan(0));
      expect(compareReleaseVersion('1', '1.0.0'), 0);
    });

    test('treats a tag and a pre-release of the same numbers as equal', () {
      expect(compareReleaseVersion('v1.2.0', '1.2.0'), 0);
      expect(compareReleaseVersion('v1.2.0-ci.9', '1.2.0'), 0);
      expect(compareReleaseVersion('V1.2.0-beta.1+4', '1.2.0+4'), 0);
      expect(compareReleaseVersion('v1.3.0', '1.2.9'), greaterThan(0));
    });

    test('rejects a version that is not numeric', () {
      expect(
        () => compareReleaseVersion('latest', '1.0.0'),
        throwsFormatException,
      );
    });
  });

  group('parseUpdateManifest', () {
    test('reads version, notes, and hashed assets', () {
      final manifest = parseUpdateManifest({
        'version': '1.4.0',
        'tag': 'v1.4.0',
        'notes': '- Faster connect\n',
        'assets': [
          {
            'platform': 'android',
            'arch': 'arm64-v8a',
            'kind': 'apk',
            'name': 'Nexo-1.4.0-android-arm64-v8a.apk',
            'sha256': _sha.toUpperCase(),
            'size': 12,
            'url': 'https://example.test/app.apk',
          },
          {
            'platform': 'android',
            'arch': 'universal',
            'name': '../evil.apk',
            'sha256': _sha,
          },
        ],
      });

      expect(manifest.version, '1.4.0');
      expect(manifest.tag, 'v1.4.0');
      expect(manifest.notes, '- Faster connect\n');
      expect(manifest.assets, hasLength(1));
      expect(manifest.assets.single.sha256, _sha);
      expect(manifest.assets.single.name, 'Nexo-1.4.0-android-arm64-v8a.apk');
    });

    test('drops an asset whose checksum is not SHA-256', () {
      final manifest = parseUpdateManifest({
        'version': '1.0.0',
        'assets': [
          {
            'platform': 'windows',
            'arch': 'amd64',
            'kind': 'exe',
            'name': 'Nexo.exe',
            'sha256': 'not-a-hash',
          },
        ],
      });

      expect(manifest.assets, isEmpty);
      expect(manifest.tag, 'v1.0.0');
    });

    test('refuses a manifest without a version', () {
      expect(() => parseUpdateManifest({'notes': 'hi'}), throwsFormatException);
    });
  });

  group('selectUpdateAsset', () {
    final manifest = parseUpdateManifest(
      buildReleaseManifest(
        version: '1.4.0',
        tag: 'v1.4.0',
        repository: 'Shahen777/nexo-app',
        notes: 'notes',
        files: [
          (name: 'Nexo-1.4.0-android-arm64-v8a.apk', sha256: _sha, size: 10),
          (name: 'Nexo-1.4.0-android.apk', sha256: _shaB, size: 30),
          (name: 'Nexo-1.4.0-android-armeabi-v7a.apk', sha256: _sha, size: 9),
          (name: 'Nexo-1.4.0-windows-amd64-setup.exe', sha256: _sha, size: 40),
          (name: 'Nexo-1.4.0-windows-amd64.zip', sha256: _sha, size: 50),
          (name: 'Nexo-1.4.0-macos-universal.dmg', sha256: _sha, size: 60),
          (name: 'Nexo-1.4.0-macos-arm64.dmg', sha256: _shaB, size: 61),
          (name: 'Nexo-1.4.0-linux-amd64.AppImage', sha256: _sha, size: 70),
          (name: 'Nexo-1.4.0-linux-amd64.deb', sha256: _shaB, size: 71),
          (name: 'Nexo-1.4.0-linux-amd64.rpm', sha256: _sha, size: 72),
          (name: 'SHA256SUMS', sha256: _sha, size: 1),
        ],
      ),
    );

    test('picks the ABI apk and falls back to the universal apk', () {
      final arm64 = selectUpdateAsset(
        manifest,
        const UpdateHost(platform: 'android', arch: 'arm64'),
        preferredKind: 'apk',
      );
      final x64 = selectUpdateAsset(
        manifest,
        const UpdateHost(platform: 'android', arch: 'amd64'),
        preferredKind: 'apk',
      );

      expect(arm64?.name, 'Nexo-1.4.0-android-arm64-v8a.apk');
      expect(x64?.name, 'Nexo-1.4.0-android.apk');
      expect(x64?.arch, 'universal');
    });

    test('prefers the Windows installer over the portable zip', () {
      final asset = selectUpdateAsset(
        manifest,
        const UpdateHost(platform: 'windows', arch: 'amd64'),
        preferredKind: 'exe',
      );

      expect(asset?.kind, 'exe');
    });

    test('prefers a macOS build for this CPU over the universal image', () {
      final asset = selectUpdateAsset(
        manifest,
        const UpdateHost(platform: 'macos', arch: 'arm64'),
        preferredKind: 'dmg',
      );

      expect(asset?.name, 'Nexo-1.4.0-macos-arm64.dmg');
    });

    test('follows the Linux package the user is running', () {
      final image = selectUpdateAsset(
        manifest,
        const UpdateHost(platform: 'linux', arch: 'amd64'),
        preferredKind: 'appimage',
      );
      final deb = selectUpdateAsset(
        manifest,
        const UpdateHost(platform: 'linux', arch: 'amd64'),
        preferredKind: 'deb',
      );
      final rpm = selectUpdateAsset(
        manifest,
        const UpdateHost(platform: 'linux', arch: 'amd64'),
        preferredKind: preferredInstallKind(
          const UpdateHost(platform: 'linux', arch: 'amd64'),
          linuxAppImage: false,
          linuxRpm: true,
        ),
      );

      expect(image?.kind, 'appimage');
      expect(deb?.kind, 'deb');
      expect(rpm?.kind, 'rpm');
    });
  });

  group('mirror urls', () {
    test('asks a custom mirror, then ours, and keeps GitHub last', () {
      expect(
        manifestCandidateUrls(
          mirrorBase: 'https://files.example/latest.json/',
          repository: 'Shahen777/nexo-app',
        ),
        [
          'https://files.example/latest.json',
          'https://app.bingod.ru/latest.json',
          'https://nl.bingod.ru:9443/latest.json',
          'https://github.com/Shahen777/nexo-app/releases/latest/download/latest.json',
        ],
      );
    });

    test('the NL mirror saved by 1.0.0 goes after Cloudflare', () {
      expect(
        manifestCandidateUrls(
          mirrorBase: 'https://nl.bingod.ru:9443',
          repository: 'Shahen777/nexo-app',
        ).take(2),
        [
          'https://app.bingod.ru/latest.json',
          'https://nl.bingod.ru:9443/latest.json',
        ],
      );
      expect(
        manifestCandidateUrls(
          mirrorBase: '',
          repository: 'Shahen777/nexo-app',
        ).first,
        'https://app.bingod.ru/latest.json',
      );
      expect(normalizeMirrorBase(''), isNull);
      expect(normalizeMirrorBase('ftp://files.example'), isNull);
    });

    test('tries the mirror file, then the manifest url, then GitHub', () {
      expect(
        assetDownloadUrls(
          name: 'Nexo-1.4.0-android.apk',
          url:
              'https://github.com/Shahen777/nexo-app/releases/download/v1.4.0/Nexo-1.4.0-android.apk',
          mirrorBase: 'nl.bingod.ru:9443',
          repository: 'Shahen777/nexo-app',
          tag: 'v1.4.0',
        ),
        [
          'https://app.bingod.ru/Nexo-1.4.0-android.apk',
          'https://nl.bingod.ru:9443/Nexo-1.4.0-android.apk',
          'https://github.com/Shahen777/nexo-app/releases/download/v1.4.0/Nexo-1.4.0-android.apk',
        ],
      );
    });

    test('rejects a file name that leaves the update directory', () {
      expect(releaseFileName(r'..\Nexo.apk'), isNull);
      expect(releaseFileName('dir/Nexo.apk'), 'Nexo.apk');
    });
  });

  test('checksum comparison ignores case and rejects other strings', () {
    expect(sha256Equals(_sha.toUpperCase(), _sha), isTrue);
    expect(sha256Equals('abc', _sha), isFalse);
  });

  test('a GitHub release without latest.json still names the version', () {
    final manifest = manifestFromGitHubRelease({
      'tag_name': 'v1.5.0',
      'body': '- Notes',
    });

    expect(manifest?.version, 'v1.5.0');
    expect(compareReleaseVersion(manifest!.version, '1.4.0'), greaterThan(0));
    expect(manifest.assets, isEmpty);
    expect(manifestFromGitHubRelease({'body': 'no tag'}), isNull);
  });

  test('a prerelease tag stays off the stable update channel', () {
    expect(tagIsPrerelease('v0.9.3-pre.1'), isTrue);
    expect(tagIsPrerelease('v0.9.2-ci.4'), isTrue);
    expect(tagIsPrerelease('v1.0.0'), isFalse);

    final pre = parseUpdateManifest({
      'version': '0.9.3',
      'tag': 'v0.9.3-pre.1',
      'assets': <Object>[],
    });
    expect(pre.prerelease, isTrue);
    expect(offerStableUpdate(pre, '0.9.2'), isFalse);

    final stable = parseUpdateManifest({
      'version': '1.0.0',
      'tag': 'v1.0.0',
      'assets': <Object>[],
    });
    expect(offerStableUpdate(stable, '0.9.2'), isTrue);
  });

  test('Fedora is an rpm install and Ubuntu is a deb install', () {
    expect(
      osReleaseIsRpm('NAME="Fedora Linux"\nID=fedora\nVERSION_ID="40"\n'),
      isTrue,
    );
    expect(osReleaseIsRpm('ID=rocky\nID_LIKE="rhel centos fedora"\n'), isTrue);
    expect(osReleaseIsRpm('ID=ubuntu\nID_LIKE=debian\n'), isFalse);
    expect(
      preferredInstallKind(
        const UpdateHost(platform: 'linux', arch: 'amd64'),
        linuxAppImage: false,
        linuxRpm: false,
      ),
      'deb',
    );
  });

  test('installer scripts wait for this process and then replace it', () {
    expect(windowsSilentInstallArguments, contains('/RELAUNCH=1'));
    expect(windowsSilentInstallArguments, contains('/VERYSILENT'));
    expect(macOSReplaceScript(), contains('cp -R'));
    expect(macOSReplaceScript(), contains('open'));
    expect(linuxAppImageReplaceScript(), contains('chmod +x'));
    expect(linuxRelaunchScript(), contains('kill -0'));
  });

  test('a writable directory can receive the macOS bundle', () async {
    final parent = await Directory.systemTemp.createTemp('nexo-mac-');
    addTearDown(() => parent.delete(recursive: true));

    expect(
      await macDestinationWritable(p.join(parent.path, 'Nexo.app')),
      isTrue,
    );
  });
}
