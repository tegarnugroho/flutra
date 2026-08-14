import 'dart:io';

import 'package:flutra/domain/entities/jdk_release.dart';
import 'package:flutra/infrastructure/archive/archive_extractor.dart';
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

    test('the tar.gz layout Adoptium serves to Linux is found too', () {
      // No .exe: the Linux archive's launcher is a bare `java`.
      _touch(p.join(root.path, 'jdk-17.0.12+7', 'bin', 'java'));

      expect(
        JdkInstallService.findJdkHome(root.path),
        p.join(root.path, 'jdk-17.0.12+7'),
      );
    });

    test('an archive with no wrapper folder is found at the root', () {
      _touch(p.join(root.path, 'bin', 'java.exe'));

      expect(JdkInstallService.findJdkHome(root.path), root.path);
    });

    test('a macOS bundle keeps its JDK two levels further down', () {
      _touch(
        p.join(root.path, 'jdk-21.jdk', 'Contents', 'Home', 'bin', 'java'),
      );

      expect(
        JdkInstallService.findJdkHome(root.path),
        p.join(root.path, 'jdk-21.jdk', 'Contents', 'Home'),
      );
    });

    test('a bin folder holding no launcher is not a JDK', () {
      // The test is bin/java, not the presence of bin: the path returned here
      // is the one the app registers and later runs.
      _touch(p.join(root.path, 'jdk-21', 'bin', 'README'));

      expect(JdkInstallService.findJdkHome(root.path), isNull);
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

  group('executableTargets', () {
    late Directory root;

    setUp(() => root = _temp());
    tearDown(() => root.deleteSync(recursive: true));

    test('every launcher in bin, plus the helper outside it', () {
      _touch(p.join(root.path, 'bin', 'java'));
      _touch(p.join(root.path, 'bin', 'javac'));
      _touch(p.join(root.path, 'lib', 'jspawnhelper'));
      // Not executable, and not in the list.
      _touch(p.join(root.path, 'lib', 'modules'));
      _touch(p.join(root.path, 'release'));

      final targets = ArchiveExtractor.executableTargets(root.path);

      expect(
        targets.map(p.basename).toSet(),
        {'java', 'javac', 'jspawnhelper'},
      );
    });

    test('a JDK without the optional helpers yields only bin', () {
      _touch(p.join(root.path, 'bin', 'java'));

      expect(
        ArchiveExtractor.executableTargets(root.path).map(p.basename),
        ['java'],
      );
    });

    test('nothing to chmod is an empty list, not a throw', () {
      expect(
        ArchiveExtractor.executableTargets(p.join(root.path, 'missing')),
        isEmpty,
      );
    });

    test('directories inside bin are not chmod targets', () {
      Directory(p.join(root.path, 'bin', 'server')).createSync(recursive: true);

      expect(ArchiveExtractor.executableTargets(root.path), isEmpty);
    });
  });

  group('checkDownloadedSize', () {
    const published = 190 * 1024 * 1024;

    test('the size the API published is the size that passes', () {
      expect(
        JdkInstallService.checkDownloadedSize(
          actual: published,
          expected: published,
        ),
        isNull,
      );
    });

    test('a connection that dropped says so, with both sizes', () {
      final message = JdkInstallService.checkDownloadedSize(
        actual: published ~/ 2,
        expected: published,
      );

      expect(message, contains('stopped early'));
      expect(message, contains('95.0 MB'));
      expect(message, contains('190.0 MB'));
    });

    test('more bytes than published is also a discard', () {
      expect(
        JdkInstallService.checkDownloadedSize(
          actual: published + 1024,
          expected: published,
        ),
        contains('larger than published'),
      );
    });

    test('an empty file fails whether or not a size was published', () {
      expect(
        JdkInstallService.checkDownloadedSize(actual: 0, expected: published),
        contains('empty'),
      );
      expect(
        JdkInstallService.checkDownloadedSize(actual: 0, expected: null),
        contains('empty'),
      );
    });

    test('an API that published no size cannot fail the check', () {
      // Azul's listing carries a size; a vendor that stops doing so must not
      // start failing every install.
      expect(
        JdkInstallService.checkDownloadedSize(actual: 123, expected: null),
        isNull,
      );
      expect(
        JdkInstallService.checkDownloadedSize(actual: 123, expected: 0),
        isNull,
      );
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
