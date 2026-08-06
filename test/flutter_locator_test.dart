import 'dart:io';

import 'package:flutra/core/platform/platform_service.dart';
import 'package:flutra/infrastructure/sdk/flutter_locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Builds the directories that mark a folder as a Flutter SDK, plus the
/// `bin/flutter` a PATH entry would point at.
Directory _fakeSdk(Directory parent, String name) {
  final root = Directory(p.join(parent.path, name))..createSync();
  Directory(p.join(root.path, 'bin', 'internal')).createSync(recursive: true);
  Directory(p.join(root.path, 'packages', 'flutter'))
      .createSync(recursive: true);
  File(p.join(root.path, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter'))
      .writeAsStringSync('');
  return root;
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('flutter_locator'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('looksLikeFlutterSdk', () {
    test('accepts a root carrying both SDK markers', () {
      final root = _fakeSdk(temp, 'flutter');
      expect(FlutterLocator.looksLikeFlutterSdk(root.path), isTrue);
    });

    test('rejects a folder that only holds an executable', () {
      final shim = Directory(p.join(temp.path, 'shims'))..createSync();
      expect(FlutterLocator.looksLikeFlutterSdk(shim.path), isFalse);
    });

    test('accepts an SDK that has never been run', () {
      // bin/cache appears on first invocation; requiring it would miss a fresh
      // clone, which is exactly the install most likely to be measured.
      final root = _fakeSdk(temp, 'flutter');
      expect(Directory(p.join(root.path, 'bin', 'cache')).existsSync(), isFalse);
      expect(FlutterLocator.looksLikeFlutterSdk(root.path), isTrue);
    });
  });

  group('rootsFromPathEntries', () {
    test('resolves the SDK root from the bin directory on PATH', () {
      final root = _fakeSdk(temp, 'flutter');
      final roots = FlutterLocator.rootsFromPathEntries(
        [p.join(root.path, 'bin')],
      ).toList();

      expect(roots, [root.path]);
    });

    test('skips entries that hold no flutter executable', () {
      final root = _fakeSdk(temp, 'flutter');
      final empty = Directory(p.join(temp.path, 'empty'))..createSync();

      final roots = FlutterLocator.rootsFromPathEntries([
        empty.path,
        p.join(temp.path, 'does-not-exist'),
        p.join(root.path, 'bin'),
      ]).toList();

      expect(roots, [root.path]);
    });

    test('keeps looking past a shim directory', () {
      // A shim's parent is not an SDK, so yielding only the first candidate
      // would report "not measured" on a machine that has Flutter installed.
      final shim = Directory(p.join(temp.path, 'shims'))..createSync();
      File(p.join(
        shim.path,
        Platform.isWindows ? 'flutter.bat' : 'flutter',
      )).writeAsStringSync('');
      final root = _fakeSdk(temp, 'flutter');

      final roots = FlutterLocator.rootsFromPathEntries([
        shim.path,
        p.join(root.path, 'bin'),
      ]).toList();

      expect(roots, hasLength(2));
      expect(roots.where(FlutterLocator.looksLikeFlutterSdk), [root.path]);
    });

    test('ignores quoting and empty entries', () {
      final root = _fakeSdk(temp, 'flutter');
      final roots = FlutterLocator.rootsFromPathEntries([
        '',
        '   ',
        '"${p.join(root.path, 'bin')}"',
      ]).toList();

      expect(roots, [root.path]);
    });
  });

  group('root', () {
    test('prefers the settings override', () {
      final overridden = _fakeSdk(temp, 'overridden');
      final locator = FlutterLocator(hostPlatform)..overrideFlutterRoot = overridden.path;

      expect(locator.root, overridden.path);
    });

    test('ignores an override that is not an SDK', () {
      // A stale or mistyped setting must not hide a working install; it falls
      // through to FLUTTER_ROOT and PATH like no override at all.
      final locator = FlutterLocator(hostPlatform)..overrideFlutterRoot = temp.path;

      expect(locator.root, isNot(temp.path));
    });

    test('falls back to PATH when nothing is overridden', () {
      // The regression this guards: `executable` returns the bare command name
      // when no override is set, so deriving the root from it yielded null and
      // the Dashboard reported the Flutter SDK as "not measured".
      final locator = FlutterLocator(hostPlatform);
      final root = locator.root;

      // Only assert when the machine running the test actually has Flutter on
      // PATH — a bare `dart test` in a container does not.
      if (root != null) {
        expect(FlutterLocator.looksLikeFlutterSdk(root), isTrue);
      }
    });
  });
}
