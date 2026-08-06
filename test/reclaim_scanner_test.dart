import 'package:flutra/domain/entities/reclaimable_item.dart';
import 'package:flutra/domain/entities/sdk_package.dart';
import 'package:flutra/infrastructure/sdk/reclaim_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

SdkPackage installed(String path, {String? location}) => SdkPackage(
      path: path,
      description: path,
      state: PackageState.installed,
      location: location,
    );

List<ReclaimableItem> scan(
  List<SdkPackage> packages, {
  Map<String, String> avdUsage = const {},
}) =>
    ReclaimScanner.supersededItems(
      packages: packages,
      sdkRoot: r'C:\Sdk',
      avdUsage: avdUsage,
    );

void main() {
  group('supersededItems', () {
    test('lists every build-tools below the newest, never the newest', () {
      final items = scan([
        installed('build-tools;34.0.0'),
        installed('build-tools;35.0.0'),
        installed('build-tools;36.0.0'),
      ]);

      expect(items.map((i) => i.id), ['build-tools;34.0.0', 'build-tools;35.0.0']);
      expect(items.first.reason, 'Superseded by build-tools 36.0.0');
      expect(items.first.supersededBy, 'build-tools;36.0.0');
    });

    test('a lone version of a family is never superseded', () {
      expect(scan([installed('build-tools;36.0.0')]), isEmpty);
    });

    test('compares versions numerically, not as text', () {
      // "9.0.0" must not beat "10.0.0" the way a string sort would.
      final items = scan([
        installed('build-tools;9.0.0'),
        installed('build-tools;10.0.0'),
      ]);
      expect(items.single.id, 'build-tools;9.0.0');
    });

    test('never lists the SDK-running packages', () {
      final items = scan([
        installed('platform-tools'),
        installed('emulator'),
        installed('cmdline-tools;latest'),
        installed('tools'),
      ]);
      expect(items, isEmpty);
    });

    test('a system image is only superseded within its own tag and ABI', () {
      final items = scan([
        installed('system-images;android-34;google_apis;x86_64'),
        installed('system-images;android-35;google_apis;x86_64'),
        // A different ABI is not a replacement for the x86_64 pair above.
        installed('system-images;android-35;google_apis;arm64-v8a'),
      ]);

      expect(
        items.map((i) => i.id),
        ['system-images;android-34;google_apis;x86_64'],
      );
    });

    test('an image an AVD is built on is blocked, not offered', () {
      final items = scan(
        [
          installed('system-images;android-34;google_apis;x86_64'),
          installed('system-images;android-35;google_apis;x86_64'),
        ],
        avdUsage: const {
          'system-images;android-34;google_apis;x86_64': 'Pixel_8',
        },
      );

      expect(items.single.isBlocked, isTrue);
      expect(items.single.blockedReason, 'In use by AVD "Pixel_8"');
      expect(items.single.isSafeDefault, isFalse);
    });

    test('platforms and ndk carry a warning, sources do not', () {
      final items = scan([
        installed('platforms;android-34'),
        installed('platforms;android-36'),
        installed('sources;android-34'),
        installed('sources;android-36'),
        installed('ndk;26.1.10909125'),
        installed('ndk;27.0.12077973'),
      ]);

      ReclaimableItem byId(String id) => items.firstWhere((i) => i.id == id);

      expect(byId('platforms;android-34').warnings, isNotEmpty);
      expect(byId('platforms;android-34').warnings.first, contains('API 34'));
      expect(byId('ndk;26.1.10909125').warnings, isNotEmpty);
      // Sources are just documentation; removing one costs nothing at build
      // time, so it is the kind that may be ticked by default.
      expect(byId('sources;android-34').warnings, isEmpty);
      expect(byId('sources;android-34').isSafeDefault, isTrue);
    });

    test('resolves the folder from the reported location when there is one',
        () {
      final items = scan([
        installed('build-tools;34.0.0', location: r'build-tools\34.0.0'),
        installed('build-tools;36.0.0'),
      ]);
      expect(items.single.folderPath, r'C:\Sdk\build-tools\34.0.0');
    });

    test('falls back to the package id as a path when none is reported', () {
      final items = scan([
        installed('system-images;android-34;google_apis;x86_64'),
        installed('system-images;android-35;google_apis;x86_64'),
      ]);
      expect(
        items.single.folderPath,
        r'C:\Sdk\system-images\android-34\google_apis\x86_64',
      );
    });

    test('ignores packages that are only available, not installed', () {
      final items = ReclaimScanner.supersededItems(
        packages: [
          installed('build-tools;36.0.0'),
          const SdkPackage(
            path: 'build-tools;34.0.0',
            description: 'old',
            state: PackageState.available,
          ),
        ],
        sdkRoot: r'C:\Sdk',
      );
      expect(items, isEmpty, reason: 'nothing on disk to reclaim');
    });
  });

  group('parseAvdImageUsage', () {
    test('reads the image path out of a config.ini', () {
      final usage = ReclaimScanner.parseAvdImageUsage({
        'Pixel_8': 'avd.ini.encoding=UTF-8\n'
            r'image.sysdir.1 = system-images\android-34\google_apis\x86_64\'
            '\nhw.lcd.density=440',
      });

      expect(usage, {
        'system-images;android-34;google_apis;x86_64': 'Pixel_8',
      });
    });

    test('an AVD with no image line contributes nothing', () {
      final usage = ReclaimScanner.parseAvdImageUsage({
        'Broken': 'avd.ini.encoding=UTF-8',
      });
      expect(usage, isEmpty);
    });
  });

  group('compareSdkVersions', () {
    test('orders dotted versions and API levels numerically', () {
      expect(compareSdkVersions('36.0.0', '34.0.0'), greaterThan(0));
      expect(compareSdkVersions('android-35', 'android-9'), greaterThan(0));
      expect(compareSdkVersions('34.0.0', '34.0.0'), 0);
    });

    test('a preview level sorts above the numbered ones', () {
      // Preview platforms follow the release they are named after.
      expect(
        compareSdkVersions('android-TiramisuPrivacySandbox', 'android-33'),
        greaterThan(0),
      );
    });
  });
}
