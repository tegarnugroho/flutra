import 'package:android_sdk_manager/domain/entities/sdk_package.dart';
import 'package:android_sdk_manager/infrastructure/repositories/sdk_repository_impl.dart';
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

void main() {
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
