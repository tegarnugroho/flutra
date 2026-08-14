import 'dart:io';

import 'package:flutra/domain/entities/sdk_package.dart';
import 'package:flutra/infrastructure/repositories/sdk_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = '''
Installed packages:
  Path                                        | Version | Description                       | Location
  -------                                     | ------- | -------                           | -------
  build-tools;35.0.0                          | 35.0.0  | Android SDK Build-Tools 35        | build-tools\\35.0.0
  emulator                                    | 34.1.0  | Android Emulator                  | emulator
  platform-tools                              | 34.0.5  | Android SDK Platform-Tools        | platform-tools
  system-images;android-34;google_apis;x86_64 | 7       | Google APIs Intel x86_64          | system-images\\android-34\\google_apis\\x86_64

Available Packages:
  Path                                        | Version | Description
  -------                                     | ------- | -------
  build-tools;36.0.0                          | 36.0.0  | Android SDK Build-Tools 36
  platforms;android-35                        | 1       | Android SDK Platform 35

Available Updates:
  ID                                          | Installed | Available
  -------                                     | -------   | -------
  emulator                                    | 34.1.0    | 35.1.0
''';

/// Captured verbatim from a real `sdkmanager --list`, progress bar and all —
/// the point of these is the bytes the tool actually emits, so nothing in them
/// is hand-written or tidied up.
String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  // The two captures differ in every way that has broken this parser: the
  // Windows one mixes CRLF section headers with LF rows, the Linux one has no
  // "Installed packages" section at all because the SDK it came from was one
  // bootstrap old.
  group('parseListing on a captured Windows listing', () {
    final listing = SdkRepositoryImpl.parseListing(
      fixture('sdkmanager_list_windows.txt'),
    );
    SdkPackage byPath(String path) =>
        listing.packages.firstWhere((e) => e.path == path);

    test('reads the sections despite mixed CRLF and LF line endings', () {
      expect(listing.hasSections, isTrue);
      expect(listing.hasAvailableSection, isTrue);
    });

    test('skips the progress bar the tool draws with carriage returns', () {
      // The whole preamble arrives as one \r-separated line; none of it is a
      // package, and none of it contains a pipe.
      expect(
        listing.packages.where((p) => p.path.contains('%')),
        isEmpty,
      );
      expect(
        listing.packages.where((p) => p.path.contains('Loading')),
        isEmpty,
      );
    });

    test('parses installed packages with their location column', () {
      final buildTools = byPath('build-tools;36.0.0');
      expect(buildTools.state, PackageState.installed);
      expect(buildTools.installedVersion, '36.0.0');
      expect(buildTools.description, 'Android SDK Build-Tools 36');
      expect(buildTools.location, r'build-tools\36.0.0');
    });

    test('parses the wide, variably-padded available rows', () {
      final addOn = byPath('add-ons;addon-google_apis-google-21');
      expect(addOn.state, PackageState.available);
      expect(addOn.availableVersion, '1');
      expect(addOn.description, 'Google APIs');
    });

    test('keeps installed and available apart', () {
      expect(
        listing.packages.where((p) => p.state == PackageState.installed),
        isNotEmpty,
      );
      expect(
        listing.packages.where((p) => p.state == PackageState.available),
        isNotEmpty,
      );
    });
  });

  group('parseListing on a captured Linux listing', () {
    // This is the exact shape the bug produced nothing for: a freshly
    // bootstrapped SDK, so every package is available and none is installed.
    final listing = SdkRepositoryImpl.parseListing(
      fixture('sdkmanager_list_linux.txt'),
    );

    test('an SDK with nothing installed still parses its catalogue', () {
      expect(listing.hasSections, isTrue);
      expect(listing.hasAvailableSection, isTrue);
      expect(listing.packages, isNotEmpty);
      expect(
        listing.packages.every((p) => p.state == PackageState.available),
        isTrue,
        reason: 'nothing was installed in the SDK this was captured from',
      );
    });

    test('finds the packages a first-run install needs', () {
      final paths = listing.packages.map((p) => p.path);
      expect(paths, contains('platform-tools'));
      expect(paths, contains('platforms;android-36'));
      expect(paths, contains('build-tools;36.0.0'));
      expect(paths, contains('emulator'));
    });
  });

  group('parseListing on output that is not a listing', () {
    test('the JAVA_HOME error is no sections, not an empty catalogue', () {
      // Printed to stdout, with stderr empty and exit code 1 — verbatim from a
      // Linux box with the managed JDK unreachable. Reporting this as "hasSections
      // false" is what stops it being shown as an SDK with no packages in it.
      const output = '\n'
          "ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.\n"
          '\n'
          'Please set the JAVA_HOME variable in your environment to match the\n'
          'location of your Java installation.\n';

      final listing = SdkRepositoryImpl.parseListing(output);
      expect(listing.packages, isEmpty);
      expect(listing.hasSections, isFalse);
      expect(listing.hasAvailableSection, isFalse);
    });

    test('empty output is no sections', () {
      final listing = SdkRepositoryImpl.parseListing('');
      expect(listing.hasSections, isFalse);
    });
  });

  group('parseListing tolerates format drift', () {
    test('accepts either casing of the section headers', () {
      const lower = 'installed packages:\n'
          '  Path | Version | Description | Location\n'
          '  platform-tools | 34.0.5 | Android SDK Platform-Tools | platform-tools\n'
          '\n'
          'available packages:\n'
          '  Path | Version | Description\n'
          '  platforms;android-35 | 1 | Android SDK Platform 35\n';
      final listing = SdkRepositoryImpl.parseListing(lower);
      expect(listing.hasSections, isTrue);
      expect(listing.hasAvailableSection, isTrue);
      expect(listing.packages, hasLength(2));
    });

    test('accepts bare CRLF throughout', () {
      final crlf = _sample.replaceAll('\n', '\r\n');
      expect(
        SdkRepositoryImpl.parseList(crlf).map((p) => p.path),
        SdkRepositoryImpl.parseList(_sample).map((p) => p.path),
      );
    });

    test('accepts an "ID" or "Package" header column', () {
      const output = 'Available Packages:\n'
          '  Package | Version | Description\n'
          '  ------- | ------- | -------\n'
          '  platforms;android-35 | 1 | Android SDK Platform 35\n';
      final listing = SdkRepositoryImpl.parseListing(output);
      expect(listing.packages, hasLength(1));
      expect(listing.packages.single.path, 'platforms;android-35');
    });

    test('skips a separator rule however wide it was drawn', () {
      const output = 'Available Packages:\n'
          '  Path | Version | Description\n'
          '  ---- | -- | ------------------------------\n'
          '  emulator | 35.1.0 | Android Emulator\n';
      expect(SdkRepositoryImpl.parseListing(output).packages, hasLength(1));
    });
  });

  group('SdkRepositoryImpl.parseList', () {
    final packages = SdkRepositoryImpl.parseList(_sample);
    SdkPackage byPath(String p) => packages.firstWhere((e) => e.path == p);

    test('parses installed, available and updatable packages', () {
      expect(packages.length, 6);
      expect(byPath('build-tools;35.0.0').state, PackageState.installed);
      expect(byPath('build-tools;36.0.0').state, PackageState.available);
      expect(byPath('emulator').state, PackageState.updatable);
    });

    test('captures versions for each state', () {
      expect(byPath('build-tools;35.0.0').installedVersion, '35.0.0');
      expect(byPath('platforms;android-35').availableVersion, '1');

      final emulator = byPath('emulator');
      expect(emulator.installedVersion, '34.1.0');
      expect(emulator.availableVersion, '35.1.0');
      expect(emulator.hasUpdate, isTrue);
    });

    test('derives categories from the path prefix', () {
      expect(byPath('platform-tools').category, PackageCategory.platformTools);
      expect(byPath('build-tools;35.0.0').category, PackageCategory.buildTools);
      expect(byPath('platforms;android-35').category, PackageCategory.platforms);
      expect(byPath('system-images;android-34;google_apis;x86_64').category,
          PackageCategory.systemImages);
    });

    test('sorts by category then path', () {
      final cats = packages.map((p) => p.category.index).toList();
      final sorted = [...cats]..sort();
      expect(cats, sorted);
    });
  });

  group('SdkRepositoryImpl.parseList cost', () {
    /// A payload the size of a real `sdkmanager --list`: the machine this was
    /// profiled on reports 556 packages over 584 lines / 110KB.
    String bigListing() {
      final rows = StringBuffer('Installed packages:\n')
        ..writeln('  Path | Version | Description | Location');
      for (var i = 0; i < 600; i++) {
        rows.writeln('  system-images;android-$i;google_apis;x86_64 | $i.0 | '
            'Google APIs Intel x86_64 System Image $i | system-images\\a$i');
      }
      return rows.toString();
    }

    test('parses a full listing in well under one frame', () {
      final input = bigListing();
      // Warm the JIT so this measures the parse, not first-call compilation.
      SdkRepositoryImpl.parseList(input);

      final sw = Stopwatch()..start();
      final packages = SdkRepositoryImpl.parseList(input);
      sw.stop();

      expect(packages, hasLength(600));
      // A tripwire, not a benchmark. Profiling put this at ~1.7ms on a debug
      // VM, which is why the Dashboard parses on the UI isolate instead of
      // paying for an Isolate.run hop. If a change ever makes this quadratic,
      // that decision has to be revisited — this is what catches it.
      expect(sw.elapsedMilliseconds, lessThan(50),
          reason: 'parseList got dramatically slower; re-check whether the '
              'Dashboard should still parse on the UI isolate');
    });
  });
}
