import 'package:flutra/domain/entities/jdk_compatibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('compares numerically, not as strings', () {
      // The string compare this replaces put 8.10 below 8.4.
      expect(compareVersions('8.10', '8.4'), 1);
      expect(compareVersions('8.4', '8.10'), -1);
      expect(compareVersions('8.4', '8.4'), 0);
    });

    test('missing components count as zero', () {
      expect(compareVersions('8', '8.0.0'), 0);
      expect(compareVersions('8.1', '8'), 1);
    });

    test('a pre-release suffix does not break the read', () {
      expect(compareVersions('3.29.0-1.0.pre', '3.29'), 0);
      expect(compareVersions('7.6.3', '7.6'), 1);
    });
  });

  group('minGradleForJdk', () {
    test('listed JDKs report their own minimum', () {
      expect(minGradleForJdk(17), '7.3');
      expect(minGradleForJdk(21), '8.5');
    });

    test('a JDK between entries takes the nearest one below it', () {
      // 16 is not listed; 11's minimum is the closest honest answer.
      expect(minGradleForJdk(16), '5.0');
    });

    test('anything older than the table needs no minimum', () {
      expect(minGradleForJdk(7), isNull);
    });

    test('a JDK newer than every entry has no known Gradle', () {
      expect(minGradleForJdk(99), isNull);
      expect(isUnknownNewJdk(99), isTrue);
      expect(isUnknownNewJdk(21), isFalse);
    });
  });

  group('flutterDefaultGradle', () {
    test('a Flutter version takes the newest table entry at or below it', () {
      expect(flutterDefaultGradle('3.24.5'), '8.7');
      expect(flutterDefaultGradle('3.19.0'), '8.3');
      expect(flutterDefaultGradle('3.29.2'), '8.12');
    });

    test('a Flutter older than the table, or none at all, says nothing', () {
      expect(flutterDefaultGradle('3.10.0'), isNull);
      expect(flutterDefaultGradle(null), isNull);
    });
  });

  group('jdkGradleWarning', () {
    test('stays silent when the pair works', () {
      // Flutter 3.24 ships Gradle 8.7, which runs JDK 21 (needs 8.5).
      expect(
        jdkGradleWarning(jdkMajor: 21, flutterVersion: '3.24.5'),
        isNull,
      );
      expect(jdkGradleWarning(jdkMajor: 17, flutterVersion: '3.29.0'), isNull);
    });

    test('warns when the JDK needs a newer Gradle than Flutter creates', () {
      // JDK 24 needs Gradle 8.14; Flutter 3.24 pins 8.7.
      final warning = jdkGradleWarning(jdkMajor: 24, flutterVersion: '3.24.5');

      expect(warning, isNotNull);
      expect(warning, contains('JDK 24'));
      expect(warning, contains('8.14'));
      expect(warning, contains('8.7'));
    });

    test('a JDK no Gradle supports is called out on its own', () {
      final warning = jdkGradleWarning(jdkMajor: 99, flutterVersion: '3.29.0');

      expect(warning, contains('newer than any Gradle release'));
    });

    test('says nothing when either half is unknown', () {
      expect(jdkGradleWarning(jdkMajor: null, flutterVersion: '3.24.5'), isNull);
      expect(jdkGradleWarning(jdkMajor: 21, flutterVersion: null), isNull);
      // Flutter older than the table: no claim to make.
      expect(jdkGradleWarning(jdkMajor: 24, flutterVersion: '3.10.0'), isNull);
    });
  });
}
