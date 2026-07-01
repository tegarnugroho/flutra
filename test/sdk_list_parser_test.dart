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
}
