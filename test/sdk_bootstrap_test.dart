import 'dart:io';

import 'package:flutra/application/sdk/sdk_manager_cubit.dart';
import 'package:flutra/infrastructure/sdk/sdk_bootstrap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Directory _temp() => Directory.systemTemp.createTempSync('flutra_sdk_bootstrap');

void _touch(String path) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('x');
}

void main() {
  group('classifySdkFailure', () {
    test('nothing anywhere is the bootstrap case, not an error', () {
      // The reported dead end: the page used to call this "could not query the
      // SDK" and offer Retry, which could never succeed — sdkmanager lives
      // inside the package sdkmanager installs.
      expect(
        classifySdkFailure(hasSdkRoot: false, hasSdkManager: false),
        SdkAvailability.noSdk,
      );
    });

    test('an SDK with no tools in it is the narrow repair', () {
      expect(
        classifySdkFailure(hasSdkRoot: true, hasSdkManager: false),
        SdkAvailability.sdkFoundNoCmdlineTools,
      );
    });

    test('a present sdkmanager that failed is the only Retry case', () {
      expect(
        classifySdkFailure(hasSdkRoot: true, hasSdkManager: true),
        SdkAvailability.queryFailed,
      );
    });

    test('an sdkmanager outside a recognised root still counts as present', () {
      // A locator that resolves the tool but not the root is a strange machine,
      // not an empty one: something ran, so its output is what explains this.
      expect(
        classifySdkFailure(hasSdkRoot: false, hasSdkManager: true),
        SdkAvailability.queryFailed,
      );
    });

    test('only the two toolless states offer to install anything', () {
      expect(SdkAvailability.noSdk.isBootstrappable, isTrue);
      expect(SdkAvailability.sdkFoundNoCmdlineTools.isBootstrappable, isTrue);
      expect(SdkAvailability.queryFailed.isBootstrappable, isFalse);
      expect(SdkAvailability.ok.isBootstrappable, isFalse);
    });
  });

  group('parseCmdlineToolsBuild', () {
    const manifest = '''
<sdk:sdk-repository>
  <remotePackage path="cmdline-tools;11.0">
    <archive><complete>
      <url>commandlinetools-linux-11076708_latest.zip</url>
    </complete></archive>
  </remotePackage>
  <remotePackage path="cmdline-tools;latest">
    <archive><complete>
      <url>commandlinetools-linux-13114758_latest.zip</url>
    </complete></archive>
    <archive><complete>
      <url>commandlinetools-win-13114758_latest.zip</url>
    </complete></archive>
    <archive><complete>
      <url>commandlinetools-mac-13114758_latest.zip</url>
    </complete></archive>
  </remotePackage>
</sdk:sdk-repository>
''';

    test('takes the newest build for the platform asked for', () {
      expect(
        parseCmdlineToolsBuild(manifest, 'commandlinetools-linux'),
        '13114758',
      );
    });

    test('each platform reads its own archive', () {
      expect(parseCmdlineToolsBuild(manifest, 'commandlinetools-win'),
          '13114758');
      expect(parseCmdlineToolsBuild(manifest, 'commandlinetools-mac'),
          '13114758');
    });

    test('builds compare as numbers, not as strings', () {
      // '9999999' sorts above '13114758' as text and below it as a number. The
      // string answer would hand out a years-old sdkmanager.
      const mixed = '''
      commandlinetools-linux-9999999_latest.zip
      commandlinetools-linux-13114758_latest.zip
      ''';

      expect(parseCmdlineToolsBuild(mixed, 'commandlinetools-linux'),
          '13114758');
    });

    test('a manifest without this platform yields null, so the pin is used', () {
      expect(
        parseCmdlineToolsBuild(manifest, 'commandlinetools-freebsd'),
        isNull,
      );
      expect(parseCmdlineToolsBuild('<html>404</html>', 'commandlinetools-linux'),
          isNull);
    });

    test('the pinned fallback is a plausible build number', () {
      expect(int.tryParse(SdkBootstrapService.fallbackBuild), isNotNull);
      expect(SdkBootstrapService.fallbackBuild.length, greaterThanOrEqualTo(8));
    });
  });

  group('findToolsDir', () {
    late Directory root;

    setUp(() => root = _temp());
    tearDown(() => root.deleteSync(recursive: true));

    test("Google's zip wraps the tools in cmdline-tools/", () {
      _touch(p.join(root.path, 'cmdline-tools', 'bin', 'sdkmanager'));

      expect(
        SdkBootstrapService.findToolsDir(root.path),
        p.join(root.path, 'cmdline-tools'),
      );
    });

    test('an archive with no wrapper is found at the root', () {
      _touch(p.join(root.path, 'bin', 'sdkmanager.bat'));

      expect(SdkBootstrapService.findToolsDir(root.path), root.path);
    });

    test('a folder with no sdkmanager is not the tools directory', () {
      _touch(p.join(root.path, 'cmdline-tools', 'bin', 'avdmanager'));

      expect(SdkBootstrapService.findToolsDir(root.path), isNull);
    });

    test('a path that does not exist does not throw', () {
      expect(
        SdkBootstrapService.findToolsDir(p.join(root.path, 'missing')),
        isNull,
      );
    });
  });

  group('baseline packages', () {
    test('platform-tools is the floor, because adb is', () {
      // Everything that lists a device, installs to one, or reports the ADB row
      // on the Dashboard needs adb, and adb ships in platform-tools.
      expect(SdkManagerCubit.baselinePackages, contains('platform-tools'));
    });
  });
}
