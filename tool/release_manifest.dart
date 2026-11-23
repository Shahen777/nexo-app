import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/update_manifest.dart';
import 'package:path/path.dart' as p;

/// Writes `latest.json` for the files in a release directory.
Future<void> main(List<String> arguments) async {
  final results =
      (ArgParser()
            ..addOption('version', mandatory: true)
            ..addOption('tag', mandatory: true)
            ..addOption('repository', defaultsTo: 'Shahen777/nexo-app')
            ..addOption(
              'notes',
              help: 'Release notes file. Empty when omitted.',
            )
            ..addOption('dist', defaultsTo: 'dist')
            ..addOption('out', defaultsTo: 'dist/latest.json')
            ..addFlag(
              'prerelease',
              negatable: false,
              help: 'Keep this manifest off the stable update channel.',
            ))
          .parse(arguments);

  final notesPath = results['notes'] as String?;
  final notes = notesPath == null ? '' : await File(notesPath).readAsString();
  final files = <({String name, String sha256, int size})>[];
  await for (final entity in Directory(results['dist'] as String).list()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (classifyReleaseFile(name) == null) continue;
    final digest = await sha256.bind(entity.openRead()).first;
    files.add((
      name: name,
      sha256: digest.toString(),
      size: await entity.length(),
    ));
  }
  files.sort((a, b) => a.name.compareTo(b.name));
  final document = buildReleaseManifest(
    version: results['version'] as String,
    tag: results['tag'] as String,
    repository: results['repository'] as String,
    notes: notes,
    files: files,
    prerelease: results['prerelease'] as bool,
  );
  final out = File(results['out'] as String);
  await out.parent.create(recursive: true);
  await out.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(document)}\n',
  );
  final count = (document['assets'] as List).length;
  stdout.writeln('Wrote ${out.path} ($count files)');
}
