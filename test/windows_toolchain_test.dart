import 'package:flutra/domain/entities/windows_toolchain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trimmed from a real `vswhere -products * -format json` answer.
const _vsWhereJson = r'''
[
  {
    "instanceId": "a1b2c3",
    "displayName": "Visual Studio Build Tools 2022",
    "installationVersion": "17.14.37516.0",
    "installationPath": "C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools",
    "productId": "Microsoft.VisualStudio.Product.BuildTools",
    "isComplete": true,
    "catalog": { "productMilestoneIsPreRelease": false }
  },
  {
    "instanceId": "d4e5f6",
    "displayName": "Visual Studio Community 2019",
    "installationVersion": "16.11.30.0",
    "installationPath": "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Community",
    "productId": "Microsoft.VisualStudio.Product.Community",
    "isComplete": false,
    "catalog": { "productMilestoneIsPreRelease": false }
  }
]
''';

VisualStudioInstall _install({
  String path = r'C:\VS',
  String version = '17.0.0.0',
  String productId = kBuildToolsProductId,
  bool complete = true,
  bool cpp = true,
}) => VisualStudioInstall(
  displayName: 'Build Tools',
  version: version,
  installPath: path,
  productId: productId,
  isComplete: complete,
  hasCppTools: cpp,
);

void main() {
  group('parseVsWhere', () {
    test('reads every install, newest first', () {
      final installs = parseVsWhere(_vsWhereJson);

      expect(installs, hasLength(2));
      expect(installs.first.displayName, 'Visual Studio Build Tools 2022');
      expect(installs.first.version, '17.14.37516.0');
      expect(installs.first.majorMinor, '17.14');
      expect(installs.last.isComplete, isFalse);
    });

    test('the C++ toolset comes from the second vswhere call', () {
      final without = parseVsWhere(_vsWhereJson);
      expect(without.every((i) => !i.hasCppTools), isTrue);

      final with_ = parseVsWhere(
        _vsWhereJson,
        withCppTools: {
          // Spelled differently on purpose: vswhere's two calls do not agree
          // on the trailing slash or the case.
          r'c:\program files (x86)\microsoft visual studio\2022\buildtools\',
        },
      );
      expect(with_.first.hasCppTools, isTrue);
      expect(with_.last.hasCppTools, isFalse);
    });

    test('the product decides which workload id to ask for', () {
      final installs = parseVsWhere(_vsWhereJson);

      expect(installs.first.isBuildTools, isTrue);
      expect(installs.first.cppWorkload, kBuildToolsWorkload);
      expect(installs.last.isBuildTools, isFalse);
      expect(installs.last.cppWorkload, kVisualStudioWorkload);
    });

    test('junk is an empty list, not an exception', () {
      expect(parseVsWhere(''), isEmpty);
      expect(parseVsWhere('vswhere is not recognised'), isEmpty);
      expect(parseVsWhere('[{"displayName": "no path"}]'), isEmpty);
    });
  });

  group('parseVsWherePaths', () {
    test('one path per line, blanks dropped', () {
      expect(
        parseVsWherePaths('C:\\A\n\nC:\\B\r\n'),
        [r'C:\A', r'C:\B'],
      );
    });
  });

  group('parseKitsRoot', () {
    test('reads the kit root, spaces intact', () {
      const output = r'''
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Kits\Installed Roots
    KitsRoot10    REG_SZ    C:\Program Files (x86)\Windows Kits\10\
''';

      expect(parseKitsRoot(output), r'C:\Program Files (x86)\Windows Kits\10\');
    });

    test('a missing key yields null', () {
      expect(parseKitsRoot('ERROR: The system was unable to find'), isNull);
    });
  });

  group('parseSdkVersions', () {
    test('keeps versioned folders, newest first', () {
      final sdks = parseSdkVersions(
        ['10.0.19041.0', 'wdf', '10.0.26100.0', '10.0.22621.0', 'ucrt'],
        kitRoot: r'C:\Kits\10',
      );

      expect(
        sdks.map((s) => s.version),
        ['10.0.26100.0', '10.0.22621.0', '10.0.19041.0'],
      );
      // Numeric, not lexical: 26100 is above 22621 and above 9999.
      expect(sdks.first.displayVersion, '10.0.26100');
    });

    test('a kit folder with nothing versioned in it yields nothing', () {
      expect(parseSdkVersions(['wdf', 'ucrt'], kitRoot: r'C:\Kits'), isEmpty);
    });
  });

  group('status', () {
    test('nothing installed is the missing-toolchain case', () {
      const toolchain = WindowsToolchain();

      expect(toolchain.status, WindowsToolchainStatus.missingVisualStudio);
      expect(toolchain.isReady, isFalse);
      expect(toolchain.active, isNull);
    });

    test('Visual Studio without C++ names that, not the SDK', () {
      final toolchain = WindowsToolchain(installs: [_install(cpp: false)]);

      expect(toolchain.status, WindowsToolchainStatus.missingCppTools);
    });

    test('C++ without a Windows SDK is its own state', () {
      final toolchain = WindowsToolchain(installs: [_install()]);

      expect(toolchain.status, WindowsToolchainStatus.missingSdk);
    });

    test('an interrupted install is called out before anything else', () {
      final toolchain = WindowsToolchain(
        installs: [_install(complete: false)],
        sdks: const [WindowsSdk(version: '10.0.26100.0', path: r'C:\Kits')],
      );

      expect(toolchain.status, WindowsToolchainStatus.incomplete);
    });

    test('compiler plus SDK is ready, and says nothing more', () {
      final toolchain = WindowsToolchain(
        installs: [_install()],
        sdks: const [WindowsSdk(version: '10.0.26100.0', path: r'C:\Kits')],
      );

      expect(toolchain.status, WindowsToolchainStatus.ready);
      expect(toolchain.status.detail, isNull);
      expect(toolchain.isReady, isTrue);
    });

    test('the active install is the usable one, not merely the newest', () {
      final newestWithoutCpp = _install(
        path: r'C:\VS2022',
        version: '17.14.0.0',
        cpp: false,
      );
      final olderWithCpp = _install(path: r'C:\VS2019', version: '16.11.0.0');
      final toolchain = WindowsToolchain(
        installs: [newestWithoutCpp, olderWithCpp],
      );

      expect(toolchain.active, olderWithCpp);
    });

    test('the count says how many and which SDK', () {
      final toolchain = WindowsToolchain(
        installs: [_install(), _install(path: r'C:\Other')],
        sdks: const [WindowsSdk(version: '10.0.26100.0', path: r'C:\Kits')],
      );

      expect(toolchain.countLabel, '2 installs · SDK 10.0.26100');
      expect(const WindowsToolchain().countLabel, '0 installs');
    });
  });
}
