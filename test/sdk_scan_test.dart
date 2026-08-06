import 'dart:io';

import 'package:flutra/application/settings/detected_paths_cubit.dart';
import 'package:flutra/infrastructure/sdk/sdk_locator.dart';
import 'package:flutra/infrastructure/sdk/sdk_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Creates `root/relative` (and its parents) as an empty file.
void touch(String root, List<String> segments) {
  final file = File(p.join(root, p.joinAll(segments)));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('');
}

void mkdir(String root, List<String> segments) =>
    Directory(p.join(root, p.joinAll(segments))).createSync(recursive: true);

void main() {
  group('SdkLocator.looksLikeAndroidSdk', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('sdk_scan_'));
    tearDown(() => temp.deleteSync(recursive: true));

    String sub(String name) => p.join(temp.path, name);

    test('rejects a folder that merely contains a "tools" directory', () {
      // The shape that made a disk scan report chocolatey packages, VirtualBox
      // hypervisors and C:\ itself as Android SDKs.
      mkdir(temp.path, ['dotnetfx', 'tools']);
      expect(SdkLocator.looksLikeAndroidSdk(sub('dotnetfx')), isFalse);
    });

    test('rejects an empty folder and one that does not exist', () {
      mkdir(temp.path, ['empty']);
      expect(SdkLocator.looksLikeAndroidSdk(sub('empty')), isFalse);
      expect(SdkLocator.looksLikeAndroidSdk(sub('nope')), isFalse);
    });

    test('accepts a root holding adb', () {
      touch(temp.path, [
        'sdk', 'platform-tools', Platform.isWindows ? 'adb.exe' : 'adb',
      ]);
      expect(SdkLocator.looksLikeAndroidSdk(sub('sdk')), isTrue);
    });

    test('accepts sdkmanager under any cmdline-tools version', () {
      touch(temp.path, [
        'sdk', 'cmdline-tools', '13.0', 'bin',
        Platform.isWindows ? 'sdkmanager.bat' : 'sdkmanager',
      ]);
      expect(SdkLocator.looksLikeAndroidSdk(sub('sdk')), isTrue);
    });

    test('accepts the platforms + build-tools pair, but never one alone', () {
      mkdir(temp.path, ['half', 'platforms']);
      expect(SdkLocator.looksLikeAndroidSdk(sub('half')), isFalse);

      mkdir(temp.path, ['full', 'platforms']);
      mkdir(temp.path, ['full', 'build-tools']);
      expect(SdkLocator.looksLikeAndroidSdk(sub('full')), isTrue);
    });
  });

  group('SdkScanService.startPoints', () {
    test('covers drive roots and the usual install locations', () {
      final points = SdkScanService.startPoints(
        environment: {
          'USERPROFILE': r'C:\Users\dev',
          'LOCALAPPDATA': r'C:\Users\dev\AppData\Local',
          'ProgramFiles': r'C:\Program Files',
        },
        exists: (_) => true,
      );

      expect(points, contains(r'C:\'));
      expect(points, contains(r'D:\'));
      expect(points, contains(r'C:\Users\dev'));
      expect(points, contains(r'C:\Users\dev\AppData\Local\Android'));
      expect(points, contains(r'C:\Program Files'));
    });

    test('skips what is not there, and never repeats a point', () {
      final points = SdkScanService.startPoints(
        environment: {'USERPROFILE': r'C:\Users\dev'},
        exists: (path) => path == r'C:\' || path == r'C:\Users\dev',
      );

      expect(points, [r'C:\', r'C:\Users\dev']);
      expect(points.toSet(), hasLength(points.length));
    });

    test('an unset environment still yields drives to search', () {
      final points = SdkScanService.startPoints(
        environment: const {},
        exists: (path) => path == r'C:\',
      );
      expect(points, [r'C:\']);
    });
  });

  group('DetectedPathsCubit.javaHomeOf', () {
    test('climbs out of bin to the JDK directory', () {
      expect(
        DetectedPathsCubit.javaHomeOf(r'C:\Program Files\jdk-17\bin\java.exe'),
        r'C:\Program Files\jdk-17',
      );
    });

    test('leaves a path that is already a home alone', () {
      expect(
        DetectedPathsCubit.javaHomeOf(r'C:\Program Files\jdk-17'),
        r'C:\Program Files\jdk-17',
      );
    });

    test('has nothing to say about an empty value', () {
      expect(DetectedPathsCubit.javaHomeOf('  '), isNull);
    });
  });
}
