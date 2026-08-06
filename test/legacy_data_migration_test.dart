import 'dart:io';

import 'package:flutra/infrastructure/settings/legacy_data_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory from;
  late Directory to;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('flutra_migration_');
    from = Directory(p.join(temp.path, 'old'));
    to = Directory(p.join(temp.path, 'new'));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  void seedOld() {
    from.createSync(recursive: true);
    File(p.join(from.path, 'settings.json')).writeAsStringSync('{"theme":1}');
    File(p.join(from.path, 'storage-report.json')).writeAsStringSync('{}');
    Directory(p.join(from.path, 'trash')).createSync();
    File(p.join(from.path, 'trash', 'entry.json')).writeAsStringSync('[]');
  }

  test('carries every file over, nested ones included', () async {
    seedOld();

    final copied = await LegacyDataMigration.migrate(from: from, to: to);

    expect(copied, 3);
    expect(File(p.join(to.path, 'settings.json')).readAsStringSync(),
        '{"theme":1}');
    expect(File(p.join(to.path, 'trash', 'entry.json')).existsSync(), isTrue);
  });

  test('leaves the old folder in place', () async {
    seedOld();
    await LegacyDataMigration.migrate(from: from, to: to);

    // A copy, not a move: an upgrade that goes wrong can still fall back.
    expect(File(p.join(from.path, 'settings.json')).existsSync(), isTrue);
  });

  test('never overwrites data the renamed build already wrote', () async {
    seedOld();
    to.createSync(recursive: true);
    File(p.join(to.path, 'settings.json')).writeAsStringSync('{"theme":2}');

    final copied = await LegacyDataMigration.migrate(from: from, to: to);

    expect(copied, 0);
    expect(File(p.join(to.path, 'settings.json')).readAsStringSync(),
        '{"theme":2}', reason: 'the newer settings must survive');
  });

  test('running twice copies nothing the second time', () async {
    seedOld();
    expect(await LegacyDataMigration.migrate(from: from, to: to), 3);
    expect(await LegacyDataMigration.migrate(from: from, to: to), 0);
  });

  test('no old folder is simply nothing to do', () async {
    expect(await LegacyDataMigration.migrate(from: from, to: to), 0);
    expect(to.existsSync(), isFalse, reason: 'no empty folder is created');
  });

  test('refuses to copy a folder onto itself', () async {
    seedOld();
    expect(await LegacyDataMigration.migrate(from: from, to: from), 0);
  });
}
