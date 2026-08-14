import 'dart:io';

import 'package:flutra/infrastructure/sdk/android_tool_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory jdks;

  /// Lays down `<name>/bin/java`, which is what makes a folder a JDK here.
  String jdk(String name, {bool withJava = true}) {
    final home = Directory(p.join(jdks.path, name))..createSync(recursive: true);
    if (withJava) {
      final bin = Directory(p.join(home.path, 'bin'))..createSync();
      File(p.join(bin.path, Platform.isWindows ? 'java.exe' : 'java'))
          .writeAsStringSync('');
    }
    return home.path;
  }

  setUp(() => jdks = Directory.systemTemp.createTempSync('managed_jdks_'));
  tearDown(() => jdks.deleteSync(recursive: true));

  group('picking the managed JDK the Android tools will run on', () {
    test('no managed JDKs is no answer, not a crash', () {
      expect(AndroidToolRunner.newestJdkIn(const []), isNull);
      expect(AndroidToolRunner.newestJdkIn([jdks.path]), isNull);
    });

    test('the only JDK installed is the one used', () {
      final only = jdk('temurin-17.0.20');
      expect(AndroidToolRunner.newestJdkIn([only]), only);
    });

    test('the newest version wins, numerically', () {
      // The bug a string sort produces: "9" sorts above "21", so the machine
      // with both would run its Android tools on the older JDK.
      final nine = jdk('temurin-9.0.4');
      final twentyOne = jdk('temurin-21.0.3');
      final seventeen = jdk('temurin-17.0.20');

      expect(
        AndroidToolRunner.newestJdkIn([nine, twentyOne, seventeen]),
        twentyOne,
      );
    });

    test('compares each version component numerically', () {
      final low = jdk('temurin-17.0.9');
      final high = jdk('temurin-17.0.20');

      expect(AndroidToolRunner.newestJdkIn([low, high]), high);
    });

    test('a half-unpacked folder with no java in it is not a JDK', () {
      // What a download killed mid-extract leaves behind. Handing it to
      // sdkmanager as JAVA_HOME would swap one silent failure for another.
      final broken = jdk('temurin-21.0.3', withJava: false);
      final usable = jdk('temurin-17.0.20');

      expect(AndroidToolRunner.newestJdkIn([broken, usable]), usable);
    });

    test('a vendor name with dashes in it still parses its version', () {
      final a = jdk('graalvm-community-21.0.2');
      final b = jdk('graalvm-community-17.0.9');

      expect(AndroidToolRunner.newestJdkIn([a, b]), a);
    });
  });

  group('isJavaHome', () {
    test('accepts either spelling of the java binary', () {
      expect(AndroidToolRunner.isJavaHome(jdk('temurin-17.0.20')), isTrue);
    });

    test('rejects a directory that merely exists', () {
      expect(
        AndroidToolRunner.isJavaHome(jdk('temurin-17.0.20', withJava: false)),
        isFalse,
      );
      expect(AndroidToolRunner.isJavaHome(p.join(jdks.path, 'nope')), isFalse);
    });
  });
}
