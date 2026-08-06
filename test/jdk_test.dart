import 'package:flutra/domain/entities/jdk.dart';
import 'package:flutter_test/flutter_test.dart';

Jdk _jdk(String path, {JdkSource source = JdkSource.disk, String? version}) =>
    Jdk(path: path, source: source, version: version);

void main() {
  group('parseReleaseFile', () {
    test('reads the quoted values a JDK release file holds', () {
      const content = '''
IMPLEMENTOR="Eclipse Adoptium"
JAVA_VERSION="17.0.11"
OS_ARCH="x86_64"
MODULES="java.base java.compiler"
''';

      final values = parseReleaseFile(content);

      expect(values['JAVA_VERSION'], '17.0.11');
      expect(values['IMPLEMENTOR'], 'Eclipse Adoptium');
      expect(values['OS_ARCH'], 'x86_64');
    });

    test('unquoted values and comments are handled too', () {
      final values = parseReleaseFile('# a comment\nJAVA_VERSION=21\n\n');

      expect(values['JAVA_VERSION'], '21');
      expect(values.containsKey('# a comment'), isFalse);
    });

    test('a value containing = keeps the rest of the line', () {
      final values = parseReleaseFile('SOURCE=".:git:a=b"');

      expect(values['SOURCE'], '.:git:a=b');
    });
  });

  group('javaMajorVersion', () {
    test('modern versions report the major first', () {
      expect(javaMajorVersion('17.0.11'), 17);
      expect(javaMajorVersion('21'), 21);
      expect(javaMajorVersion('24.0.1'), 24);
    });

    test('Java 8 and earlier hide the major in the second component', () {
      expect(javaMajorVersion('1.8.0_401'), 8);
      expect(javaMajorVersion('1.7.0'), 7);
    });

    test('nonsense reads as unknown rather than as a wrong number', () {
      expect(javaMajorVersion('unknown'), isNull);
      expect(javaMajorVersion(''), isNull);
    });
  });

  group('parseJavaVersionOutput', () {
    test('reads the quoted version java prints on stderr', () {
      const output = '''
openjdk version "17.0.11" 2024-04-16
OpenJDK Runtime Environment Temurin-17.0.11+9 (build 17.0.11+9)
''';

      expect(parseJavaVersionOutput(output), '17.0.11');
    });

    test('an unquoted build still yields its version', () {
      expect(parseJavaVersionOutput('openjdk version 21.0.3'), '21.0.3');
    });

    test('output that says nothing about a version yields null', () {
      expect(parseJavaVersionOutput('Error: could not find java.dll'), isNull);
    });
  });

  group('registry parsing', () {
    const output = r'''
HKEY_LOCAL_MACHINE\SOFTWARE\JavaSoft\JDK\17.0.11
    JavaHome    REG_SZ    C:\Program Files\Eclipse Adoptium\jdk-17.0.11-hotspot

HKEY_LOCAL_MACHINE\SOFTWARE\JavaSoft\JDK\21.0.3
    JavaHome    REG_SZ    C:\Program Files\Java\jdk-21
''';

    test('collects every JavaHome, paths with spaces intact', () {
      expect(parseRegistryJavaHomes(output), [
        r'C:\Program Files\Eclipse Adoptium\jdk-17.0.11-hotspot',
        r'C:\Program Files\Java\jdk-21',
      ]);
    });

    test('a key with no values yields nothing', () {
      expect(parseRegistryJavaHomes('ERROR: The system was unable'), isEmpty);
    });

    test('a single named value is read on its own', () {
      const single = r'''
HKEY_LOCAL_MACHINE\SOFTWARE\Android Studio
    Path    REG_SZ    C:\Program Files\Android\Android Studio
''';

      expect(
        parseRegistryValue(single, 'Path'),
        r'C:\Program Files\Android\Android Studio',
      );
      expect(parseRegistryValue(single, 'Missing'), isNull);
    });
  });

  group('parseFlutterJdkDir', () {
    test('reads the configured directory', () {
      const output = '''
Settings:
  enable-windows-desktop: true
  jdk-dir: C:\\Program Files\\Java\\jdk-17

Analytics reporting is currently enabled.
''';

      expect(parseFlutterJdkDir(output), r'C:\Program Files\Java\jdk-17');
    });

    test('an unset setting is not a path', () {
      expect(parseFlutterJdkDir('  jdk-dir: (Not set)'), isNull);
      expect(parseFlutterJdkDir('Settings:\n  enable-web: true'), isNull);
    });
  });

  group('samePath', () {
    test('case, separators and a trailing slash name the same directory', () {
      expect(samePath(r'C:\Java\jdk-17', r'c:\java\JDK-17'), isTrue);
      expect(samePath(r'C:\Java\jdk-17\', r'C:\Java\jdk-17'), isTrue);
      expect(samePath('C:/Java/jdk-17', r'C:\Java\jdk-17'), isTrue);
    });

    test('a sibling directory is not the same one', () {
      expect(samePath(r'C:\Java\jdk-17', r'C:\Java\jdk-171'), isFalse);
    });
  });

  group('resolveActiveJdk', () {
    final adoptium = _jdk(r'C:\Java\jdk-17', version: '17.0.11');
    final zulu = _jdk(r'C:\Java\zulu-21', version: '21.0.3');
    final jbr = _jdk(r'C:\AS\jbr', source: JdkSource.androidStudio);

    test('flutter config wins over everything else', () {
      final active = resolveActiveJdk(
        [adoptium, zulu, jbr],
        flutterJdkDir: r'C:\Java\zulu-21',
        javaHome: r'C:\Java\jdk-17',
        pathJdk: r'C:\AS\jbr',
      );

      expect(active!.jdk, zulu);
      expect(active.source, ActiveJdkSource.flutterConfig);
    });

    test('JAVA_HOME is next, because Gradle reads it', () {
      final active = resolveActiveJdk(
        [adoptium, zulu],
        javaHome: r'c:\java\JDK-17\',
        pathJdk: r'C:\Java\zulu-21',
      );

      expect(active!.jdk, adoptium);
      expect(active.source, ActiveJdkSource.javaHome);
    });

    test('PATH is the last resort', () {
      final active = resolveActiveJdk([adoptium], pathJdk: r'C:\Java\jdk-17');

      expect(active!.source, ActiveJdkSource.path);
    });

    test('a setting pointing somewhere unlisted falls through', () {
      final active = resolveActiveJdk(
        [adoptium],
        flutterJdkDir: r'D:\deleted\jdk-11',
        javaHome: r'C:\Java\jdk-17',
      );

      expect(active!.source, ActiveJdkSource.javaHome);
    });

    test('nothing configured anywhere means no active JDK', () {
      expect(resolveActiveJdk([adoptium]), isNull);
      expect(resolveActiveJdk(const [], javaHome: r'C:\Java\jdk-17'), isNull);
    });
  });

  group('validity', () {
    test('only a full JDK can be chosen', () {
      const jdk = Jdk(path: r'C:\x', source: JdkSource.disk, version: '17');
      expect(jdk.isSelectable, isTrue);
      expect(jdk.validity.reason, isNull);

      const jre = Jdk(
        path: r'C:\x',
        source: JdkSource.disk,
        version: '17',
        validity: JdkValidity.jreOnly,
      );
      expect(jre.isSelectable, isFalse);
      expect(jre.validity.reason, 'JRE only');

      const broken = Jdk(
        path: r'C:\x',
        source: JdkSource.disk,
        validity: JdkValidity.invalid,
      );
      expect(broken.isSelectable, isFalse);
      expect(broken.displayName, 'JDK');
    });

    test('the display name carries the major version', () {
      expect(_jdk(r'C:\x', version: '1.8.0_401').displayName, 'JDK 8');
      expect(_jdk(r'C:\x', version: '21.0.3').displayName, 'JDK 21');
    });
  });
}
