import 'package:flutra/domain/entities/windows_toolchain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trimmed from a real `vswhere -products * -format json` answer.
///
/// `isPrerelease` is a JSON boolean while `catalog.productMilestoneIsPreRelease`
/// is the *string* "False" — copied verbatim, because a hard cast on the second
/// one used to abort the whole scan.
const _vsWhereJson = r'''
[
  {
    "instanceId": "a1b2c3",
    "displayName": "Visual Studio Build Tools 2022",
    "installationVersion": "17.14.37516.0",
    "installationPath": "C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools",
    "productId": "Microsoft.VisualStudio.Product.BuildTools",
    "isComplete": true,
    "isPrerelease": false,
    "catalog": {
      "productMilestoneIsPreRelease": "False",
      "productPreReleaseMilestoneSuffix": "1.0"
    }
  },
  {
    "instanceId": "d4e5f6",
    "displayName": "Visual Studio Community 2019",
    "installationVersion": "16.11.30.0",
    "installationPath": "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Community",
    "productId": "Microsoft.VisualStudio.Product.Community",
    "isComplete": false,
    "isPrerelease": false,
    "catalog": { "productMilestoneIsPreRelease": "False" }
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

    test('a boolean spelled as a word does not abort the scan', () {
      // vswhere writes `isPrerelease: false` and, in the same document,
      // `catalog.productMilestoneIsPreRelease: "False"`. Casting the second
      // one to bool threw, and the page reported an empty machine.
      final installs = parseVsWhere(_vsWhereJson);

      expect(installs, hasLength(2));
      expect(installs.first.isPrerelease, isFalse);
    });

    test('a prerelease is read from either spelling', () {
      const boolean = r'''
[{"installationPath": "C:\\A", "isPrerelease": true}]
''';
      const word = r'''
[{"installationPath": "C:\\B",
  "catalog": {"productMilestoneIsPreRelease": "True"}}]
''';

      expect(parseVsWhere(boolean).single.isPrerelease, isTrue);
      expect(parseVsWhere(word).single.isPrerelease, isTrue);
    });

    test('a field of the wrong type falls back instead of throwing', () {
      const odd = r'''
[{"installationPath": "C:\\A", "displayName": 42, "isComplete": "false"}]
''';
      final install = parseVsWhere(odd).single;

      expect(install.displayName, 'Visual Studio');
      expect(install.isComplete, isFalse);
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

      expect(
        parseRegistryValue(output, 'KitsRoot10'),
        r'C:\Program Files (x86)\Windows Kits\10\',
      );
    });

    test('a missing key yields null', () {
      expect(
        parseRegistryValue('ERROR: The system was unable to find', 'KitsRoot10'),
        isNull,
      );
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

  group('parseDeveloperMode', () {
    test('reads the DWORD reg query prints as hex', () {
      const on = r'''
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock
    AllowDevelopmentWithoutDevLicense    REG_DWORD    0x1
''';
      const off = r'''
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock
    AllowDevelopmentWithoutDevLicense    REG_DWORD    0x0
''';

      expect(parseDeveloperMode(on), DeveloperModeState.on);
      expect(parseDeveloperMode(off), DeveloperModeState.off);
    });

    test('an absent key is unknown, which is not the same as off', () {
      expect(
        parseDeveloperMode('ERROR: The system was unable to find'),
        DeveloperModeState.unknown,
      );
    });
  });

  group('parseFlutterConfigFlag', () {
    /// Copied from a real `flutter config --list`, including the shapes that
    /// are not a plain true/false.
    const output = '''
All Settings:
  enable-web: true
  enable-linux-desktop: (Not set)
  enable-windows-desktop: (Not set)
  enable-fuchsia: (Not set) (Unavailable)
  enable-ios: false
  jdk-dir: C:\\Program Files\\Microsoft\\jdk-17.0.20.8-hotspot
''';

    test('reads a flag that was set', () {
      expect(
        parseFlutterConfigFlag(output, 'enable-web'),
        FlutterFlagState.on,
      );
      expect(
        parseFlutterConfigFlag(output, 'enable-ios'),
        FlutterFlagState.off,
      );
    });

    test('"(Not set)" is its own answer, not off and not a failure', () {
      // Reading this as off sent people to enable what Flutter already
      // defaults to on.
      expect(
        parseFlutterConfigFlag(output, 'enable-windows-desktop'),
        FlutterFlagState.notSet,
      );
    });

    test('a trailing "(Unavailable)" is about the platform, not the value', () {
      expect(
        parseFlutterConfigFlag(output, 'enable-fuchsia'),
        FlutterFlagState.notSet,
      );
    });

    test('a flag this Flutter never heard of is unknown', () {
      expect(
        parseFlutterConfigFlag(output, 'enable-something-else'),
        FlutterFlagState.unknown,
      );
      expect(
        parseFlutterConfigFlag('flutter: command not found', 'enable-web'),
        FlutterFlagState.unknown,
      );
    });
  });

  group('SDK floor', () {
    test('an SDK below Flutter\'s floor does not count', () {
      const old = WindowsSdk(version: '10.0.17134.0', path: r'C:\Kits');
      const floor = WindowsSdk(version: kMinimumWindowsSdk, path: r'C:\Kits');
      const newer = WindowsSdk(version: '10.0.26100.0', path: r'C:\Kits');

      expect(old.meetsFloor, isFalse);
      expect(floor.meetsFloor, isTrue);
      expect(newer.meetsFloor, isTrue);
    });
  });

  group('requirements', () {
    WindowsRequirement of(
      WindowsToolchain toolchain,
      WindowsRequirementKind kind,
    ) => toolchain.requirements.firstWhere((r) => r.kind == kind);

    const sdk = WindowsSdk(version: '10.0.26100.0', path: r'C:\Kits');

    /// A machine with nothing missing, so each test can break one thing.
    WindowsToolchain healthy({
      List<VisualStudioInstall>? installs,
      List<WindowsSdk>? sdks,
      DeveloperModeState developerMode = DeveloperModeState.on,
      FlutterFlagState windowsDesktop = FlutterFlagState.on,
    }) => WindowsToolchain(
      installs: installs ?? [_install()],
      sdks: sdks ?? const [sdk],
      developerMode: developerMode,
      windowsDesktop: windowsDesktop,
    );

    test('a healthy machine has nothing to fix', () {
      final toolchain = healthy();

      expect(toolchain.isReady, isTrue);
      expect(toolchain.unmet, isEmpty);
      expect(
        toolchain.requirements.every(
          (r) => r.action == WindowsRequirementAction.none,
        ),
        isTrue,
      );
    });

    test('no Visual Studio asks for the bootstrapper', () {
      final toolchain = healthy(installs: const [], sdks: const []);

      expect(toolchain.nothingInstalled, isTrue);
      expect(
        of(toolchain, WindowsRequirementKind.cppToolchain).action,
        WindowsRequirementAction.installBuildTools,
      );
      // The SDK arrives with the workload, so it asks for the same thing.
      expect(
        of(toolchain, WindowsRequirementKind.windowsSdk).action,
        WindowsRequirementAction.installBuildTools,
      );
    });

    test('Visual Studio without C++ is modified, not reinstalled', () {
      final toolchain = healthy(installs: [_install(cpp: false)]);
      final requirement = of(toolchain, WindowsRequirementKind.cppToolchain);

      expect(requirement.satisfied, isFalse);
      expect(requirement.action, WindowsRequirementAction.addCppWorkload);
      expect(requirement.detail, contains('C++ workload not installed'));
    });

    test('an interrupted install is repaired', () {
      final toolchain = healthy(installs: [_install(complete: false)]);

      expect(
        of(toolchain, WindowsRequirementKind.cppToolchain).action,
        WindowsRequirementAction.repair,
      );
    });

    test('a missing SDK is added to the install that has the compiler', () {
      final toolchain = healthy(sdks: const []);
      final requirement = of(toolchain, WindowsRequirementKind.windowsSdk);

      expect(requirement.satisfied, isFalse);
      expect(requirement.action, WindowsRequirementAction.addWindowsSdk);
    });

    test('an SDK below the floor reads as missing, and says why', () {
      final toolchain = healthy(
        sdks: const [WindowsSdk(version: '10.0.17134.0', path: r'C:\Kits')],
      );
      final requirement = of(toolchain, WindowsRequirementKind.windowsSdk);

      expect(requirement.satisfied, isFalse);
      expect(requirement.detail, contains(kMinimumWindowsSdk));
    });

    test('older SDKs are counted, not listed', () {
      final toolchain = healthy(
        sdks: const [
          sdk,
          WindowsSdk(version: '10.0.22621.0', path: r'C:\Kits'),
          WindowsSdk(version: '10.0.19041.0', path: r'C:\Kits'),
        ],
      );

      expect(
        of(toolchain, WindowsRequirementKind.windowsSdk).detail,
        '10.0.26100.0  + 2 older',
      );
    });

    test('Developer Mode off sends the user to Settings', () {
      final toolchain = healthy(developerMode: DeveloperModeState.off);
      final requirement = of(toolchain, WindowsRequirementKind.developerMode);

      expect(requirement.satisfied, isFalse);
      expect(
        requirement.action,
        WindowsRequirementAction.openDeveloperSettings,
      );
      expect(requirement.caption, contains('return and refresh'));
    });

    test('a Developer Mode key that could not be read is not a problem', () {
      final toolchain = healthy(developerMode: DeveloperModeState.unknown);
      final requirement = of(toolchain, WindowsRequirementKind.developerMode);

      // Telling someone to change a setting that may already be right is
      // worse than saying nothing.
      expect(requirement.satisfied, isTrue);
      expect(requirement.action, WindowsRequirementAction.none);
    });

    test('windows-desktop off is one flutter config away', () {
      final toolchain = healthy(windowsDesktop: FlutterFlagState.off);
      final requirement = of(toolchain, WindowsRequirementKind.flutterConfig);

      expect(requirement.satisfied, isFalse);
      expect(
        requirement.action,
        WindowsRequirementAction.enableWindowsDesktop,
      );
    });

    test('an untouched flag is not a problem — Flutter defaults it on', () {
      final toolchain = healthy(windowsDesktop: FlutterFlagState.notSet);
      final requirement = of(toolchain, WindowsRequirementKind.flutterConfig);

      // `(Not set)` used to read as "could not be asked", which said the app
      // had failed at something it had in fact read correctly.
      expect(requirement.satisfied, isTrue);
      expect(requirement.action, WindowsRequirementAction.none);
      expect(requirement.detail, contains('default applies'));
    });

    test('no Flutter to ask is not a failure of this machine', () {
      final toolchain = healthy(windowsDesktop: FlutterFlagState.unknown);

      expect(
        of(toolchain, WindowsRequirementKind.flutterConfig).satisfied,
        isTrue,
      );
    });

    test('every unmet requirement is counted for the panel', () {
      final toolchain = healthy(
        installs: [_install(cpp: false)],
        sdks: const [],
        developerMode: DeveloperModeState.off,
        windowsDesktop: FlutterFlagState.off,
      );

      expect(toolchain.unmet, hasLength(4));
      expect(toolchain.isReady, isFalse);
    });
  });

  group('installs', () {
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
      expect(toolchain.otherInstalls, [newestWithoutCpp]);
    });

    test('the summary names the install and the SDK', () {
      final toolchain = WindowsToolchain(
        installs: [_install(version: '17.14.37516.0')],
        sdks: const [WindowsSdk(version: '10.0.26100.0', path: r'C:\Kits')],
      );

      expect(toolchain.summary, 'Build Tools 17.14 · SDK 10.0.26100');
      expect(const WindowsToolchain().summary, isEmpty);
    });
  });
}
