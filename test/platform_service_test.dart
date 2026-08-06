import 'package:android_sdk_manager/core/platform/platform_service.dart';
import 'package:android_sdk_manager/domain/entities/doctor_issue.dart';
import 'package:android_sdk_manager/domain/entities/doctor_report.dart';
import 'package:android_sdk_manager/domain/entities/linux_distro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _unixHome = {'HOME': '/home/dev'};

void main() {
  group('executable naming', () {
    test('Windows adds the extension each kind actually uses', () {
      final windows = WindowsPlatformService(environment: const {});
      // A binary is .exe; the SDK's wrappers are .bat — using one for the other
      // is how a path silently resolves to nothing.
      expect(windows.executableName('adb'), 'adb.exe');
      expect(windows.scriptName('sdkmanager'), 'sdkmanager.bat');
      expect(windows.flutterExecutable, 'flutter.bat');
    });

    test('Unix uses the bare name for both', () {
      for (final unix in [
        LinuxPlatformService(environment: _unixHome),
        MacosPlatformService(environment: _unixHome),
      ]) {
        expect(unix.executableName('adb'), 'adb');
        expect(unix.scriptName('sdkmanager'), 'sdkmanager');
        expect(unix.flutterExecutable, 'flutter');
      }
    });
  });

  group('default Android SDK locations', () {
    test('Linux looks under the home directory', () {
      final paths =
          LinuxPlatformService(environment: _unixHome).defaultAndroidSdkPaths;
      expect(paths.first, '/home/dev/Android/Sdk');
    });

    test('macOS looks under Library', () {
      final paths =
          MacosPlatformService(environment: _unixHome).defaultAndroidSdkPaths;
      expect(paths, ['/home/dev/Library/Android/sdk']);
    });

    test('Windows prefers LOCALAPPDATA', () {
      final paths = WindowsPlatformService(environment: {
        'LOCALAPPDATA': r'C:\Users\dev\AppData\Local',
        'USERPROFILE': r'C:\Users\dev',
      }).defaultAndroidSdkPaths;
      expect(paths.first, r'C:\Users\dev\AppData\Local\Android\Sdk');
    });

    test('an unset home yields nothing rather than a bogus relative path', () {
      expect(
        LinuxPlatformService(environment: const {}).defaultAndroidSdkPaths,
        isEmpty,
      );
    });
  });

  group('resolveAvdHome', () {
    test('ANDROID_AVD_HOME wins outright', () {
      expect(
        resolveAvdHome({'ANDROID_AVD_HOME': '/data/avds'}, '/home/dev'),
        '/data/avds',
      );
    });

    test('ANDROID_USER_HOME is honoured — it used to be ignored', () {
      // The modern replacement for ANDROID_SDK_HOME. Missing it meant a
      // relocated AVD folder was invisible to the app.
      expect(
        resolveAvdHome({'ANDROID_USER_HOME': '/data/android'}, '/home/dev',
            context: p.posix),
        '/data/android/avd',
      );
    });

    test('the legacy ANDROID_SDK_HOME still resolves', () {
      expect(
        resolveAvdHome({'ANDROID_SDK_HOME': '/legacy'}, '/home/dev',
            context: p.posix),
        '/legacy/.android/avd',
      );
    });

    test('falls back to the home directory', () {
      expect(
        resolveAvdHome(const {}, '/home/dev', context: p.posix),
        '/home/dev/.android/avd',
      );
    });

    test('no home at all means no answer, not a relative guess', () {
      expect(resolveAvdHome(const {}, null), isNull);
    });

    test('Windows reads the same variables', () {
      // Previously Windows only ever looked at USERPROFILE.
      final windows = WindowsPlatformService(environment: {
        'USERPROFILE': r'C:\Users\dev',
        'ANDROID_AVD_HOME': r'D:\avds',
      });
      expect(windows.avdHome, r'D:\avds');
    });
  });

  group('macosJdkHome', () {
    test('points inside the bundle, where bin/java actually is', () {
      expect(
        macosJdkHome('/Library/Java/JavaVirtualMachines/temurin-21.jdk'),
        '/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home',
      );
    });
  });

  group('parseLinuxFamily', () {
    test('reads a plain Fedora release', () {
      expect(
        parseLinuxFamily('NAME="Fedora Linux"\nID=fedora\nVERSION_ID=41'),
        LinuxPackageFamily.fedora,
      );
    });

    test('resolves a derivative through ID_LIKE', () {
      // Mint's own ID matches nothing; ID_LIKE is what identifies it.
      expect(
        parseLinuxFamily('ID=linuxmint\nID_LIKE="ubuntu debian"'),
        LinuxPackageFamily.debian,
      );
      expect(
        parseLinuxFamily('ID=manjaro\nID_LIKE=arch'),
        LinuxPackageFamily.arch,
      );
    });

    test('handles quoted and unquoted values alike', () {
      expect(parseLinuxFamily('ID="ubuntu"'), LinuxPackageFamily.debian);
      expect(parseLinuxFamily('ID=ubuntu'), LinuxPackageFamily.debian);
    });

    test('an unknown distro is unknown, not a wrong guess', () {
      expect(
        parseLinuxFamily('ID=void\nID_LIKE=nothing'),
        LinuxPackageFamily.unknown,
      );
      expect(parseLinuxFamily(''), LinuxPackageFamily.unknown);
    });

    test('an unknown distro offers every command, to copy rather than run', () {
      final commands = installCommandsFor(LinuxPackageFamily.unknown);
      expect(commands, hasLength(3));
      // A recognised one offers exactly the command that fits it.
      expect(installCommandsFor(LinuxPackageFamily.debian).single.command,
          contains('apt-get'));
    });
  });

  group('per-platform doctor issues', () {
    List<DoctorIssue> match(String category, List<String> lines, String os) =>
        issuesFor(
          category: category,
          status: DoctorStatus.error,
          detailLines: lines,
          operatingSystem: os,
        );

    test('Visual Studio issues never appear off Windows', () {
      const line = 'X Visual Studio not installed; this is necessary to '
          'develop for Windows.';
      expect(match('Visual Studio', [line], 'windows').single.id, 'vs_missing');
      // On Linux the same words could only come from a stale log; offering a
      // Windows installer for it would be nonsense.
      expect(match('Visual Studio', [line], 'linux').single.id, 'unknown');
    });

    test('the Linux dependency issue is Linux-only', () {
      const line = 'X clang++ is required for Linux development.';
      expect(
        match('Linux toolchain', [line], 'linux').single.id,
        'linux_deps_missing',
      );
      expect(match('Linux toolchain', [line], 'macos').single.id, 'unknown');
    });

    test('the Xcode issues are macOS-only', () {
      expect(
        match('Xcode', ['X Xcode end user license agreement not signed'],
                'macos')
            .single
            .id,
        'xcode_license',
      );
      expect(
        match('Xcode', ['X CocoaPods not installed'], 'macos').single.id,
        'cocoapods_missing',
      );
      expect(
        match('Xcode', ['X CocoaPods not installed'], 'windows').single.id,
        'unknown',
      );
    });

    test('the fallback points at the running platform own guide', () {
      final linux = match('Network resources', ['X something odd'], 'linux');
      expect(linux.single.url, endsWith('/linux'));
      final macos = match('Network resources', ['X something odd'], 'macos');
      expect(macos.single.url, endsWith('/macos'));
    });

    test('the shared issues stay on every platform', () {
      for (final os in ['windows', 'linux', 'macos']) {
        expect(
          match('Android toolchain', ['X Android licenses not accepted'], os)
              .single
              .id,
          'android_licenses',
          reason: 'licences need accepting everywhere',
        );
      }
    });
  });
}
