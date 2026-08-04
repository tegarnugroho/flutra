import 'dart:convert';

import 'package:android_sdk_manager/domain/entities/flutter_release.dart';
import 'package:flutter_test/flutter_test.dart';

/// A miniature stand-in for releases_windows.json covering every messy shape
/// the real file contains.
const _json = '''
{
  "base_url": "https://storage.googleapis.com/flutter_infra_release/releases",
  "current_release": { "beta": "beta-hash-1", "dev": "dev-hash-1", "stable": "stable-hash-new" },
  "releases": [
    { "hash": "stable-hash-new", "channel": "stable", "version": "3.13.3",
      "dart_sdk_version": "3.1.2", "dart_sdk_arch": "x64",
      "release_date": "2023-09-13T19:57:50.620730Z",
      "archive": "windows/flutter_windows_3.13.3-stable.zip", "sha256": "aa" },
    { "hash": "stable-hash-old", "channel": "stable", "version": "3.13.3",
      "dart_sdk_version": "3.1.2",
      "release_date": "2023-09-07T22:03:51.637649Z" },
    { "hash": "promoted-hash", "channel": "stable", "version": "2.5.0",
      "release_date": "2021-09-08T00:00:00.000000Z" },
    { "hash": "promoted-hash", "channel": "beta", "version": "2.5.0",
      "release_date": "2021-09-01T00:00:00.000000Z" },
    { "hash": "beta-hash-1", "channel": "beta", "version": "3.9.0-0.1.pre",
      "dart_sdk_version": "3.13.0 (build 3.13.0-282.3.beta)",
      "release_date": "2023-04-05T00:00:00.000000Z" },
    { "hash": "beta-hash-0", "channel": "beta", "version": "3.9.0-0.1.pre",
      "release_date": "2023-04-01T00:00:00.000000Z" },
    { "hash": "legacy-hash", "channel": "stable", "version": "v1.12.13+hotfix.5",
      "release_date": "2020-01-01T00:00:00.000000Z" },
    { "hash": "dev-hash-1", "channel": "dev", "version": "1.26.0-1.0.pre",
      "release_date": "2020-11-01T00:00:00.000000Z" },
    { "hash": "future-hash", "channel": "experimental", "version": "9.9.9",
      "release_date": "2030-01-01T00:00:00.000000Z" }
  ]
}
''';

FlutterReleasesIndex _index() => FlutterReleasesIndex.fromJson(
    jsonDecode(_json) as Map<String, dynamic>);

void main() {
  group('FlutterReleasesIndex.forChannel', () {
    test('collapses re-released versions to the latest release date', () {
      final stable = _index().forChannel('stable');
      final matches = stable.where((r) => r.version == '3.13.3').toList();
      expect(matches, hasLength(1));
      expect(matches.single.hash, 'stable-hash-new');
    });

    test('keeps a promoted release in both channels', () {
      final index = _index();
      expect(index.forChannel('stable').any((r) => r.hash == 'promoted-hash'),
          isTrue);
      expect(
          index.forChannel('beta').any((r) => r.hash == 'promoted-hash'), isTrue);
    });

    test('sorts by release date descending, ignoring file order', () {
      final dates = _index()
          .forChannel('stable')
          .map((r) => r.releaseDate!)
          .toList();
      for (var i = 1; i < dates.length; i++) {
        expect(dates[i - 1].isAfter(dates[i]), isTrue);
      }
    });

    test('excludes other channels', () {
      expect(_index().forChannel('stable').every((r) => r.channel == 'stable'),
          isTrue);
    });
  });

  group('parsing tolerance', () {
    test('parses the retired dev channel and unknown channels', () {
      final index = _index();
      expect(index.forChannel('dev'), hasLength(1));
      expect(index.forChannel('experimental'), hasLength(1));
    });

    test('absent dart_sdk_version stays null', () {
      final legacy = _index()
          .forChannel('stable')
          .firstWhere((r) => r.version.startsWith('v'));
      expect(legacy.dartSdkVersion, isNull);
      expect(legacy.displayDartVersion, isNull);
    });

    test('beta dart version drops the build qualifier for display', () {
      final beta = _index().forChannel('beta').first;
      expect(beta.dartSdkVersion, '3.13.0 (build 3.13.0-282.3.beta)');
      expect(beta.displayDartVersion, '3.13.0');
    });
  });

  group('version strings', () {
    test('legacy v prefix is stripped for display but kept as the git tag', () {
      final legacy = _index()
          .forChannel('stable')
          .firstWhere((r) => r.version.startsWith('v'));
      expect(legacy.displayVersion, '1.12.13+hotfix.5');
      expect(legacy.gitTag, 'v1.12.13+hotfix.5');
    });

    test('modern versions are unchanged', () {
      final modern = _index()
          .forChannel('stable')
          .firstWhere((r) => r.version == '3.13.3');
      expect(modern.displayVersion, '3.13.3');
      expect(modern.gitTag, '3.13.3');
    });
  });

  group('current release', () {
    test('latestFor resolves the channel hash', () {
      expect(_index().latestFor('stable')?.version, '3.13.3');
      expect(_index().latestFor('beta')?.hash, 'beta-hash-1');
    });

    test('byHash finds an unlisted commit as null', () {
      expect(_index().byHash('not-a-release'), isNull);
      expect(_index().byHash('legacy-hash')?.version, 'v1.12.13+hotfix.5');
    });
  });

  test('malformed payload yields an empty index rather than throwing', () {
    final index = FlutterReleasesIndex.fromJson(const {'releases': 'nope'});
    expect(index.releases, isEmpty);
    expect(index.forChannel('stable'), isEmpty);
  });
}
