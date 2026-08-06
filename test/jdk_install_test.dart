import 'dart:io';

import 'package:flutra/domain/entities/jdk_release.dart';
import 'package:flutra/infrastructure/java/jdk_install_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Directory _temp() =>
    Directory.systemTemp.createTempSync('flutra_jdk_install_test');

void _touch(String path) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('x');
}

void main() {
  group('findJdkHome', () {
    late Directory root;

    setUp(() => root = _temp());
    tearDown(() => root.deleteSync(recursive: true));

    test('finds the JDK one level down, which is how both vendors ship', () {
      _touch(p.join(root.path, 'jdk-21.0.12+8', 'bin', 'java.exe'));

      expect(
        JdkInstallService.findJdkHome(root.path),
        p.join(root.path, 'jdk-21.0.12+8'),
      );
    });

    test('an archive with no wrapper folder is found at the root', () {
      _touch(p.join(root.path, 'bin', 'java.exe'));

      expect(JdkInstallService.findJdkHome(root.path), root.path);
    });

    test('an archive holding no JDK yields null rather than a wrong path', () {
      _touch(p.join(root.path, 'readme.txt'));
      Directory(p.join(root.path, 'docs')).createSync();

      expect(JdkInstallService.findJdkHome(root.path), isNull);
    });

    test('a path that does not exist is not a JDK', () {
      expect(
        JdkInstallService.findJdkHome(p.join(root.path, 'missing')),
        isNull,
      );
    });
  });

  group('sha256OfFile', () {
    late Directory root;

    setUp(() => root = _temp());
    tearDown(() => root.deleteSync(recursive: true));

    test('matches the digest the vendors publish', () async {
      final file = File(p.join(root.path, 'archive.zip'));
      file.writeAsStringSync('flutra');

      // Computed independently: `python -c "...sha256(b'flutra')"`. A verifier
      // that agreed with itself but not with the world would pass every test
      // and reject every real download.
      expect(
        await JdkInstallService.sha256OfFile(file),
        '95e0bc9eeb2228949a871c68320df9b08f45e7397a8bda9208bce4c9d7241523',
      );
    });

    test('one changed byte changes the digest', () async {
      final file = File(p.join(root.path, 'archive.zip'));
      file.writeAsStringSync('flutra');
      final original = await JdkInstallService.sha256OfFile(file);

      file.writeAsStringSync('flutrb');

      expect(await JdkInstallService.sha256OfFile(file), isNot(original));
    });
  });

  group('install folder naming', () {
    test('the folder says which vendor and version it holds', () {
      const temurin = JdkRelease(
        vendor: JdkVendor.adoptium,
        major: 21,
        version: '21.0.12',
        downloadUrl: 'x',
        fileName: 'x.zip',
      );
      const zulu = JdkRelease(
        vendor: JdkVendor.azul,
        major: 17,
        version: '17.0.13',
        downloadUrl: 'x',
        fileName: 'x.zip',
      );

      expect(temurin.installFolderName, 'temurin-21.0.12');
      expect(zulu.installFolderName, 'zulu-17.0.13');
    });
  });

  group('parseZuluChecksum', () {
    test('reads the hash the listing does not carry', () {
      const body = '''
{
  "name": "zulu21.52.15-ca-jdk21.0.12-win_x64.zip",
  "sha256_hash": "3c06e6693fd6fa725b985e66798a6a8293c75f52b793490754ad3c54d3d8b5a6",
  "size": 210632000
}
''';

      expect(
        parseZuluChecksum(body),
        '3c06e6693fd6fa725b985e66798a6a8293c75f52b793490754ad3c54d3d8b5a6',
      );
    });

    test('a detail answer without a hash yields null, never an empty string',
        () {
      expect(parseZuluChecksum('{"name": "x.zip"}'), isNull);
      expect(parseZuluChecksum('{"sha256_hash": ""}'), isNull);
      expect(parseZuluChecksum('<html>500</html>'), isNull);
    });
  });

  group('install stages', () {
    test('each stage says what is happening in the present tense', () {
      expect(JdkInstallStage.downloading.label, 'Downloading…');
      expect(JdkInstallStage.verifying.label, 'Verifying…');
      expect(JdkInstallStage.extracting.label, 'Extracting…');
      expect(JdkInstallStage.done.label, 'Installed');
    });
  });
}
