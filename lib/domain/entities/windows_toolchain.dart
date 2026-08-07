import 'dart:convert';

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Constants
//
// Every component id, version floor and URL this feature depends on lives
// here. They are Microsoft's identifiers, not ours: when one changes there is
// exactly one file to correct.
// ---------------------------------------------------------------------------

/// The MSVC component Flutter's Windows build needs.
///
/// This is the same component `flutter doctor` looks for — CMake needs a C++
/// compiler and the Windows SDK headers behind it.
const String kVcToolsComponent =
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64';

/// The C++ workload, per product. Build Tools has no IDE, so its workload is
/// named differently from the one in a full Visual Studio — asking for the
/// wrong one fails with an error that names neither.
const String kBuildToolsWorkload = 'Microsoft.VisualStudio.Workload.VCTools';
const String kVisualStudioWorkload =
    'Microsoft.VisualStudio.Workload.NativeDesktop';

/// The Windows SDK component to add when none is installed.
// TODO: ARM64 component IDs when targeting windows-arm64.
const String kWindowsSdkComponent =
    'Microsoft.VisualStudio.Component.Windows11SDK.22621';

/// The product id `vswhere` reports for a Build Tools install.
const String kBuildToolsProductId = 'Microsoft.VisualStudio.Product.BuildTools';

/// The oldest Windows SDK Flutter builds against.
// TODO: verify current minimum against flutter.dev docs at implementation time.
const String kMinimumWindowsSdk = '10.0.17763.0';

/// The official Build Tools bootstrapper — a ~4 MB stub that downloads the
/// rest itself.
// TODO: confirm channel URL current at impl time.
const String kBuildToolsBootstrapperUrl =
    'https://aka.ms/vs/17/release/vs_BuildTools.exe';

/// The Settings page that turns Developer Mode on. Flutra never writes the
/// registry key behind it: that lives in HKLM and needs admin.
const String kDeveloperModeSettingsUri = 'ms-settings:developers';

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

/// One Visual Studio or Build Tools installation.
class VisualStudioInstall extends Equatable {
  const VisualStudioInstall({
    required this.displayName,
    required this.version,
    required this.installPath,
    required this.productId,
    this.isComplete = true,
    this.isPrerelease = false,
    this.hasCppTools = false,
  });

  final String displayName;

  /// Full installation version, e.g. `17.14.37516.0`.
  final String version;

  final String installPath;

  /// e.g. `Microsoft.VisualStudio.Product.BuildTools`.
  final String productId;

  /// False when a previous install was interrupted. A half-installed
  /// toolchain fails builds in ways that name nothing useful.
  final bool isComplete;

  final bool isPrerelease;

  /// Whether the MSVC toolset Flutter needs is present.
  final bool hasCppTools;

  /// Build Tools has no IDE; a full Visual Studio does.
  bool get isBuildTools => productId == kBuildToolsProductId;

  /// The workload id to pass when adding C++ to this install.
  String get cppWorkload =>
      isBuildTools ? kBuildToolsWorkload : kVisualStudioWorkload;

  /// `17.14` — what people call the release.
  String get majorMinor {
    final parts = version.split('.');
    return parts.length < 2 ? version : '${parts[0]}.${parts[1]}';
  }

  @override
  List<Object?> get props => [installPath, version, productId, hasCppTools];
}

/// One installed Windows SDK.
class WindowsSdk extends Equatable {
  const WindowsSdk({required this.version, required this.path});

  /// e.g. `10.0.26100.0`.
  final String version;

  /// The kit root the version sits under.
  final String path;

  /// `10.0.26100` — the build people quote.
  String get displayVersion {
    final parts = version.split('.');
    return parts.length < 4 ? version : parts.take(3).join('.');
  }

  /// Whether this SDK is at or above Flutter's floor.
  bool get meetsFloor => compareWindowsVersions(version, kMinimumWindowsSdk) >= 0;

  @override
  List<Object?> get props => [version, path];
}

/// The four things a Windows desktop build needs, in the order they are read.
enum WindowsRequirementKind {
  cppToolchain,
  windowsSdk,
  developerMode,
  flutterConfig;

  String get label => switch (this) {
    WindowsRequirementKind.cppToolchain => 'Visual Studio C++ toolchain',
    WindowsRequirementKind.windowsSdk => 'Windows SDK',
    WindowsRequirementKind.developerMode => 'Developer Mode',
    WindowsRequirementKind.flutterConfig => 'Flutter windows-desktop',
  };
}

/// What can be done about a requirement that is not met.
enum WindowsRequirementAction {
  /// Nothing to do — it is satisfied.
  none,

  /// No Visual Studio at all: run the Build Tools bootstrapper.
  installBuildTools,

  /// A Visual Studio is here without C++: modify it.
  addCppWorkload,

  /// Add the Windows SDK component to the install that has the compiler.
  addWindowsSdk,

  /// Finish an install that was interrupted.
  repair,

  /// Open `ms-settings:developers` — this one is the user's to toggle.
  openDeveloperSettings,

  /// `flutter config --enable-windows-desktop`.
  enableWindowsDesktop;

  /// The button's words, or null when there is no button.
  String? get label => switch (this) {
    WindowsRequirementAction.none => null,
    WindowsRequirementAction.installBuildTools => 'Install Build Tools',
    WindowsRequirementAction.addCppWorkload => 'Add C++ workload',
    WindowsRequirementAction.addWindowsSdk => 'Install via VS Installer',
    WindowsRequirementAction.repair => 'Repair install',
    WindowsRequirementAction.openDeveloperSettings => 'Open settings',
    WindowsRequirementAction.enableWindowsDesktop => 'Enable',
  };
}

/// One row of the requirement list.
class WindowsRequirement extends Equatable {
  const WindowsRequirement({
    required this.kind,
    required this.satisfied,
    required this.detail,
    this.action = WindowsRequirementAction.none,
    this.caption,
  });

  final WindowsRequirementKind kind;
  final bool satisfied;

  /// What was detected, in the tile's mono line.
  final String detail;

  final WindowsRequirementAction action;

  /// A second line under the action, for the one case that needs explaining.
  final String? caption;

  @override
  List<Object?> get props => [kind, satisfied, detail, action, caption];
}

/// Whether Developer Mode is on. Unknown when the key could not be read —
/// which is not the same as off, and must not be reported as a problem.
enum DeveloperModeState { on, off, unknown }

/// What `flutter config --list` says about a flag.
///
/// Four states, not two: Flutter prints `(Not set)` for a flag nobody has
/// touched, and its own default then applies — which for windows-desktop means
/// enabled. Reading that as "off" would send people to fix what is not broken.
enum FlutterFlagState {
  on,
  off,

  /// Present in the list as `(Not set)`.
  notSet,

  /// Flutter could not be asked, or does not know this flag.
  unknown,
}

/// Everything the Windows toolchain page knows about this machine.
class WindowsToolchain extends Equatable {
  const WindowsToolchain({
    this.installs = const [],
    this.sdks = const [],
    this.developerMode = DeveloperModeState.unknown,
    this.windowsDesktop = FlutterFlagState.unknown,
  });

  final List<VisualStudioInstall> installs;

  /// Installed Windows SDKs, newest first.
  final List<WindowsSdk> sdks;

  final DeveloperModeState developerMode;

  /// `flutter config --list` → `enable-windows-desktop`.
  final FlutterFlagState windowsDesktop;

  /// The install a build would use: the newest complete one with C++ tools,
  /// or the newest of whatever is there.
  VisualStudioInstall? get active {
    final usable = installs.where((i) => i.hasCppTools && i.isComplete);
    if (usable.isNotEmpty) return usable.first;
    return installs.isEmpty ? null : installs.first;
  }

  /// Installs that are not the one in use — informational only.
  List<VisualStudioInstall> get otherInstalls {
    final current = active;
    return [
      for (final install in installs)
        if (install != current) install,
    ];
  }

  WindowsSdk? get newestSdk => sdks.isEmpty ? null : sdks.first;

  /// SDKs at or above Flutter's floor.
  List<WindowsSdk> get usableSdks =>
      [for (final sdk in sdks) if (sdk.meetsFloor) sdk];

  /// The four requirements, each already knowing how it would be fixed.
  List<WindowsRequirement> get requirements => [
    _cppRequirement(),
    _sdkRequirement(),
    _developerModeRequirement(),
    _flutterConfigRequirement(),
  ];

  List<WindowsRequirement> get unmet =>
      [for (final r in requirements) if (!r.satisfied) r];

  bool get isReady => unmet.isEmpty;

  /// True when there is no Visual Studio of any kind — the empty-state case.
  bool get nothingInstalled => installs.isEmpty;

  /// `VS Build Tools 2022 17.14 · SDK 10.0.26100`.
  String get summary {
    final install = active;
    final sdk = usableSdks.isEmpty ? null : usableSdks.first;
    return [
      if (install != null) '${install.displayName} ${install.majorMinor}',
      if (sdk != null) 'SDK ${sdk.displayVersion}',
    ].join(' · ');
  }

  WindowsRequirement _cppRequirement() {
    if (installs.isEmpty) {
      return const WindowsRequirement(
        kind: WindowsRequirementKind.cppToolchain,
        satisfied: false,
        detail: 'No Visual Studio or Build Tools found',
        action: WindowsRequirementAction.installBuildTools,
      );
    }
    final withCpp = installs.where((i) => i.hasCppTools).toList();
    if (withCpp.isEmpty) {
      final target = installs.first;
      return WindowsRequirement(
        kind: WindowsRequirementKind.cppToolchain,
        satisfied: false,
        detail: '${target.displayName} — C++ workload not installed',
        action: WindowsRequirementAction.addCppWorkload,
      );
    }
    final complete = withCpp.where((i) => i.isComplete).toList();
    if (complete.isEmpty) {
      return WindowsRequirement(
        kind: WindowsRequirementKind.cppToolchain,
        satisfied: false,
        detail: '${withCpp.first.displayName} — installation incomplete',
        action: WindowsRequirementAction.repair,
      );
    }
    final install = complete.first;
    return WindowsRequirement(
      kind: WindowsRequirementKind.cppToolchain,
      satisfied: true,
      detail: '${install.displayName} ${install.version}',
    );
  }

  WindowsRequirement _sdkRequirement() {
    final usable = usableSdks;
    if (usable.isEmpty) {
      return WindowsRequirement(
        kind: WindowsRequirementKind.windowsSdk,
        satisfied: false,
        detail: sdks.isEmpty
            ? 'No Windows SDK found'
            : 'Newest is ${sdks.first.displayVersion}, below the '
                  '$kMinimumWindowsSdk floor',
        // The SDK is a Visual Studio component, so it arrives the same way the
        // compiler did.
        action: installs.isEmpty
            ? WindowsRequirementAction.installBuildTools
            : WindowsRequirementAction.addWindowsSdk,
      );
    }
    final older = usable.length - 1;
    return WindowsRequirement(
      kind: WindowsRequirementKind.windowsSdk,
      satisfied: true,
      detail:
          '${usable.first.version}${older > 0 ? '  + $older older' : ''}',
    );
  }

  WindowsRequirement _developerModeRequirement() {
    return switch (developerMode) {
      // Unknown is not a problem to fix: the key could not be read, and
      // telling someone to change a setting that may already be right is
      // worse than saying nothing.
      DeveloperModeState.on || DeveloperModeState.unknown => WindowsRequirement(
        kind: WindowsRequirementKind.developerMode,
        satisfied: true,
        detail: developerMode == DeveloperModeState.on
            ? 'Enabled'
            : 'Could not be read',
      ),
      DeveloperModeState.off => const WindowsRequirement(
        kind: WindowsRequirementKind.developerMode,
        satisfied: false,
        detail: 'Disabled — plugins that use symlinks will fail to build',
        action: WindowsRequirementAction.openDeveloperSettings,
        caption: 'Enable Developer Mode, then return and refresh.',
      ),
    };
  }

  WindowsRequirement _flutterConfigRequirement() => switch (windowsDesktop) {
    FlutterFlagState.on => const WindowsRequirement(
      kind: WindowsRequirementKind.flutterConfig,
      satisfied: true,
      detail: 'enable-windows-desktop: true',
    ),
    // Untouched, so Flutter's own default applies — which is on. Offering to
    // "enable" it would be offering to fix nothing.
    FlutterFlagState.notSet => const WindowsRequirement(
      kind: WindowsRequirementKind.flutterConfig,
      satisfied: true,
      detail: 'enable-windows-desktop: (not set) — Flutter\'s default applies',
    ),
    FlutterFlagState.unknown => const WindowsRequirement(
      kind: WindowsRequirementKind.flutterConfig,
      satisfied: true,
      detail: 'Flutter could not be asked',
    ),
    FlutterFlagState.off => const WindowsRequirement(
      kind: WindowsRequirementKind.flutterConfig,
      satisfied: false,
      detail: 'enable-windows-desktop: false',
      action: WindowsRequirementAction.enableWindowsDesktop,
    ),
  };

  @override
  List<Object?> get props => [
    installs,
    sdks,
    developerMode,
    windowsDesktop,
  ];
}

// ---------------------------------------------------------------------------
// Parsers
// ---------------------------------------------------------------------------

/// Reads `vswhere -format json`.
///
/// [withCppTools] holds the install paths a second `vswhere -requires` call
/// returned, which is how the C++ toolset is detected — the JSON above does
/// not list components.
List<VisualStudioInstall> parseVsWhere(
  String body, {
  Set<String> withCppTools = const {},
}) {
  final decoded = _decodeList(body);
  if (decoded == null) return const [];

  final normalised = {for (final path in withCppTools) _normalise(path)};

  final installs = <VisualStudioInstall>[];
  for (final entry in decoded.whereType<Map<String, dynamic>>()) {
    final path = _asString(entry['installationPath']);
    if (path == null || path.isEmpty) continue;
    final catalog = entry['catalog'];
    installs.add(VisualStudioInstall(
      displayName: _asString(entry['displayName']) ?? 'Visual Studio',
      version: _asString(entry['installationVersion']) ?? '',
      installPath: path,
      productId: _asString(entry['productId']) ?? '',
      // Absent means installed, not broken: older vswhere builds omit it.
      isComplete: _asBool(entry['isComplete']) ?? true,
      // The top-level flag is a real boolean. Its counterpart inside `catalog`
      // is the string "False", which is why nothing here trusts a JSON type.
      isPrerelease:
          _asBool(entry['isPrerelease']) ??
          (catalog is Map<String, dynamic>
              ? _asBool(catalog['productMilestoneIsPreRelease'])
              : null) ??
          false,
      hasCppTools: normalised.contains(_normalise(path)),
    ));
  }

  // Newest first: that is the one a build picks up.
  installs.sort((a, b) => compareWindowsVersions(b.version, a.version));
  return installs;
}

/// Reads the install paths out of `vswhere -property installationPath`.
List<String> parseVsWherePaths(String output) => [
  for (final line in output.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

/// Reads a named `REG_SZ`/`REG_DWORD` value out of `reg query` output.
String? parseRegistryValue(String output, String name) {
  final pattern = RegExp('$name\\s+REG_[A-Z_]+\\s+(.+)\$');
  for (final line in output.split('\n')) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final value = match.group(1)!.trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// Reads `AllowDevelopmentWithoutDevLicense`, which `reg query` prints as hex.
DeveloperModeState parseDeveloperMode(String output) {
  final raw = parseRegistryValue(output, 'AllowDevelopmentWithoutDevLicense');
  if (raw == null) return DeveloperModeState.unknown;
  final value = raw.toLowerCase().startsWith('0x')
      ? int.tryParse(raw.substring(2), radix: 16)
      : int.tryParse(raw);
  if (value == null) return DeveloperModeState.unknown;
  return value == 0 ? DeveloperModeState.off : DeveloperModeState.on;
}

/// Turns the folder names under `<kit>\Include` into SDKs, newest first.
///
/// Only versioned folders count: the kit root also holds `wdf` and other
/// directories that are not SDK versions.
List<WindowsSdk> parseSdkVersions(
  Iterable<String> folderNames, {
  required String kitRoot,
}) {
  final pattern = RegExp(r'^10\.\d+\.\d+\.\d+$');
  final sdks = [
    for (final name in folderNames)
      if (pattern.hasMatch(name.trim()))
        WindowsSdk(version: name.trim(), path: kitRoot),
  ];
  sdks.sort((a, b) => compareWindowsVersions(b.version, a.version));
  return sdks;
}

/// Reads a boolean setting out of `flutter config --list`.
///
/// `(Not set)` is its own answer, not false: Flutter's default then applies,
/// and for the desktop targets that default is on. Some entries also carry a
/// trailing `(Unavailable)`, which is about the platform, not the value.
FlutterFlagState parseFlutterConfigFlag(String output, String setting) {
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('$setting:')) continue;
    final value = trimmed.substring(setting.length + 1).trim().toLowerCase();
    if (value.startsWith('true')) return FlutterFlagState.on;
    if (value.startsWith('false')) return FlutterFlagState.off;
    if (value.startsWith('(not set)')) return FlutterFlagState.notSet;
    return FlutterFlagState.unknown;
  }
  // Absent from the list: this Flutter has never heard of the flag.
  return FlutterFlagState.unknown;
}

/// Compares dotted version strings numerically: -1, 0 or 1.
int compareWindowsVersions(String a, String b) {
  final left = _components(a);
  final right = _components(b);
  for (var i = 0; i < left.length || i < right.length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}

/// Reads a JSON value that may be a bool or the *word* for one.
///
/// `vswhere` spells the same idea both ways in one document, and a hard cast
/// on the wrong one took the whole scan down with it.
bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  if (value is num) return value != 0;
  return null;
}

String? _asString(Object? value) => value is String ? value : null;

String _normalise(String path) {
  var value = path.trim().replaceAll('/', r'\');
  while (value.length > 1 && value.endsWith(r'\')) {
    value = value.substring(0, value.length - 1);
  }
  return value.toLowerCase();
}

List<int> _components(String version) => [
  for (final part in version.trim().split('.')) int.tryParse(part) ?? 0,
];

List<dynamic>? _decodeList(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is List ? decoded : null;
  } catch (_) {
    return null;
  }
}
