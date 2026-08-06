import 'package:flutra/domain/entities/jdk_release.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trimmed from a real `/v3/assets/latest/21/hotspot` answer.
const _adoptiumAssets = '''
[
  {
    "binary": {
      "architecture": "x64",
      "image_type": "jdk",
      "installer": {
        "checksum": "845a30ebafdb4cbc",
        "link": "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12%2B8/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12_8.msi",
        "name": "OpenJDK21U-jdk_x64_windows_hotspot_21.0.12_8.msi",
        "size": 190000000
      },
      "os": "windows",
      "package": {
        "checksum": "3c06e6693fd6fa725b985e66798a6a8293c75f52b793490754ad3c54d3d8b5a6",
        "link": "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12%2B8/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12_8.zip",
        "name": "OpenJDK21U-jdk_x64_windows_hotspot_21.0.12_8.zip",
        "size": 210632000
      }
    },
    "release_name": "jdk-21.0.12+8",
    "version": {
      "build": 8,
      "major": 21,
      "minor": 0,
      "openjdk_version": "21.0.12+8-LTS",
      "security": 12,
      "semver": "21.0.12+8.0.LTS"
    }
  }
]
''';

/// Trimmed from a real Azul packages answer.
const _zuluPackages = '''
[
  {
    "availability_type": "CA",
    "download_url": "https://cdn.azul.com/zulu/bin/zulu21.52.15-ca-jdk21.0.12-win_x64.zip",
    "java_version": [21, 0, 12],
    "latest": true,
    "name": "zulu21.52.15-ca-jdk21.0.12-win_x64.zip",
    "package_uuid": "aaa",
    "product": "zulu"
  },
  {
    "availability_type": "CA",
    "download_url": "https://cdn.azul.com/zulu/bin/zulu21.50.19-ca-jdk21.0.10-win_x64.zip",
    "java_version": [21, 0, 10],
    "latest": true,
    "name": "zulu21.50.19-ca-jdk21.0.10-win_x64.zip",
    "package_uuid": "bbb",
    "product": "zulu"
  },
  {
    "availability_type": "CA",
    "download_url": "https://cdn.azul.com/zulu/bin/zulu17.54.21-ca-jdk17.0.13-win_x64.zip",
    "java_version": [17, 0, 13],
    "latest": true,
    "name": "zulu17.54.21-ca-jdk17.0.13-win_x64.zip",
    "package_uuid": "ccc",
    "product": "zulu"
  },
  {
    "availability_type": "CA",
    "download_url": "https://cdn.azul.com/zulu/bin/zulu24.32.13-ca-jdk24.0.2-win_x64.msi",
    "java_version": [24, 0, 2],
    "latest": true,
    "name": "zulu24.32.13-ca-jdk24.0.2-win_x64.msi",
    "package_uuid": "ddd",
    "product": "zulu"
  }
]
''';

void main() {
  group('parseAdoptiumAvailability', () {
    test('reads the feature versions and which of them are LTS', () {
      const body = '''
{
  "available_lts_releases": [8, 11, 17, 21, 25],
  "available_releases": [8, 11, 17, 21, 24, 25, 26],
  "most_recent_lts": 25
}
''';

      final availability = parseAdoptiumAvailability(body);

      expect(availability.releases, [8, 11, 17, 21, 24, 25, 26]);
      expect(availability.lts, {8, 11, 17, 21, 25});
    });

    test('junk yields an empty availability rather than throwing', () {
      expect(parseAdoptiumAvailability('<html>502</html>').releases, isEmpty);
      expect(parseAdoptiumAvailability('[]').releases, isEmpty);
    });
  });

  group('parseAdoptiumAssets', () {
    test('takes the archive, not the installer', () {
      final releases = parseAdoptiumAssets(_adoptiumAssets, lts: {21});

      expect(releases, hasLength(1));
      final release = releases.single;
      expect(release.vendor, JdkVendor.adoptium);
      expect(release.major, 21);
      // The version loses its build and LTS qualifier for display.
      expect(release.version, '21.0.12');
      expect(release.downloadUrl, endsWith('.zip'));
      expect(release.fileName, endsWith('.zip'));
      expect(release.lts, isTrue);
    });

    test('the checksum comes with the listing, which is why this API leads',
        () {
      final release = parseAdoptiumAssets(_adoptiumAssets).single;

      expect(
        release.checksum,
        '3c06e6693fd6fa725b985e66798a6a8293c75f52b793490754ad3c54d3d8b5a6',
      );
      expect(release.sizeBytes, 210632000);
      expect(release.displaySize, '201 MB');
    });

    test('a major absent from the LTS set is not badged', () {
      final release = parseAdoptiumAssets(_adoptiumAssets, lts: {17}).single;

      expect(release.lts, isFalse);
    });

    test('an entry with no package is skipped, not half-built', () {
      const noPackage = '[{"binary": {"installer": {"link": "x.msi"}},'
          '"version": {"major": 21}}]';

      expect(parseAdoptiumAssets(noPackage), isEmpty);
    });
  });

  group('parseZuluPackages', () {
    test('keeps the newest build per major', () {
      final releases = parseZuluPackages(_zuluPackages);

      expect(releases.map((r) => r.major).toSet(), {21, 17});
      final twentyOne = releases.firstWhere((r) => r.major == 21);
      expect(twentyOne.version, '21.0.12');
      expect(twentyOne.vendor, JdkVendor.azul);
    });

    test('anything that is not a zip is dropped', () {
      final releases = parseZuluPackages(_zuluPackages);

      // The JDK 24 row in the fixture is an .msi.
      expect(releases.any((r) => r.major == 24), isFalse);
    });

    test('the listing carries no checksum, so none is invented', () {
      final release = parseZuluPackages(_zuluPackages).first;

      expect(release.checksum, isNull);
    });

    test('LTS falls back to the static set when the API will not say', () {
      final releases = parseZuluPackages(_zuluPackages);

      expect(releases.firstWhere((r) => r.major == 21).lts, isTrue);
      expect(releases.firstWhere((r) => r.major == 17).lts, isTrue);
    });
  });

  group('sortReleases', () {
    test('newest major first, so the usual pick needs no scrolling', () {
      final sorted = sortReleases([
        ...parseZuluPackages(_zuluPackages),
        ...parseAdoptiumAssets(_adoptiumAssets),
      ]);

      expect(sorted.first.major, 21);
      expect(sorted.last.major, 17);
    });
  });

  group('displaySize', () {
    test('reads in the unit a download is judged by', () {
      const base = JdkRelease(
        vendor: JdkVendor.adoptium,
        major: 21,
        version: '21.0.12',
        downloadUrl: 'x',
        fileName: 'x.zip',
      );

      expect(base.displaySize, isNull);
      expect(
        const JdkRelease(
          vendor: JdkVendor.adoptium,
          major: 21,
          version: '21',
          downloadUrl: 'x',
          fileName: 'x.zip',
          sizeBytes: 210632000,
        ).displaySize,
        '201 MB',
      );
    });
  });
}
