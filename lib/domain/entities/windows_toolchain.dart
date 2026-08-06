import 'dart:convert';

import 'package:equatable/equatable.dart';

/// The MSVC component Flutter's Windows build needs.
///
/// Flutter shells out to CMake, which needs a C++ compiler and the Windows SDK
/// headers. This is the id both Visual Studio and the Build Tools use for the
/// x64 toolset.
const String kVcToolsComponent = 'Microsoft.VisualStudio.Component.VC.Tools'
    '.x86.x64';

/// The workload to add, per product.
///
/// Build Tools has no IDE, so its C++ workload is named differently from the
/// one in a full Visual Studio — asking for the wrong one fails with an error
/// that names neither.
const String kBuildToolsWorkload = 'Microsoft.VisualStudio.Workload.VCTools';
const String kVisualStudioWorkload =
    'Microsoft.VisualStudio.Workload.NativeDesktop';

/// The product id `vswhere` reports for a Build Tools install.
const String kBuildToolsProductId =
    'Microsoft.VisualStudio.Product.BuildTools';

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

  /// False when a previous install was interrupted — the installer calls this
  /// out, and a half-installed toolchain fails builds in confusing ways.
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

  /// The version's include folder's parent — the kit root.
  final String path;

  /// `10.0.26100` — the build people quote.
  String get displayVersion {
    final parts = version.split('.');
    return parts.length < 4 ? version : parts.take(3).join('.');
  }

  @override
  List<Object?> get props => [version, path];
}

/// What is stopping a Windows desktop build, if anything.
enum WindowsToolchainStatus {
  /// Everything Flutter asks for is here.
  ready,

  /// No Visual Studio or Build Tools at all.
  missingVisualStudio,

  /// Visual Studio is here without the C++ toolset.
  missingCppTools,

  /// The C++ toolset is here but no Windows SDK is.
  missingSdk,

  /// An install was interrupted and never finished.
  incomplete;

  String get headline => switch (this) {
    WindowsToolchainStatus.ready => 'Ready for Windows builds',
    WindowsToolchainStatus.missingVisualStudio => 'Build tools not installed',
    WindowsToolchainStatus.missingCppTools => 'C++ tools missing',
    WindowsToolchainStatus.missingSdk => 'Windows SDK missing',
    WindowsToolchainStatus.incomplete => 'Installation incomplete',
  };

  /// One sentence about what it means, or null when nothing is wrong.
  String? get detail => switch (this) {
    WindowsToolchainStatus.ready => null,
    WindowsToolchainStatus.missingVisualStudio =>
      'Windows desktop builds need the MSVC compiler and the Windows SDK. '
          'Build Tools installs both without the Visual Studio IDE.',
    WindowsToolchainStatus.missingCppTools =>
      'Visual Studio is installed, but without the C++ desktop workload that '
          'Flutter compiles against.',
    WindowsToolchainStatus.missingSdk =>
      'The compiler is here, but no Windows SDK is — CMake will not find the '
          'system headers.',
    WindowsToolchainStatus.incomplete =>
      'A previous install was interrupted. Repair it before building; a '
          'half-installed toolchain fails in ways that name nothing useful.',
  };
}

/// Everything the Windows page knows about the machine's build toolchain.
class WindowsToolchain extends Equatable {
  const WindowsToolchain({
    this.installs = const [],
    this.sdks = const [],
  });

  final List<VisualStudioInstall> installs;

  /// Installed Windows SDKs, newest first.
  final List<WindowsSdk> sdks;

  /// The install a build would use: the newest complete one with C++ tools,
  /// or the newest of whatever is there.
  VisualStudioInstall? get active {
    final usable = installs.where((i) => i.hasCppTools && i.isComplete);
    if (usable.isNotEmpty) return usable.first;
    return installs.isEmpty ? null : installs.first;
  }

  WindowsSdk? get newestSdk => sdks.isEmpty ? null : sdks.first;

  WindowsToolchainStatus get status {
    if (installs.isEmpty) return WindowsToolchainStatus.missingVisualStudio;
    final withCpp = installs.where((i) => i.hasCppTools).toList();
    if (withCpp.isEmpty) return WindowsToolchainStatus.missingCppTools;
    if (withCpp.every((i) => !i.isComplete)) {
      return WindowsToolchainStatus.incomplete;
    }
    if (sdks.isEmpty) return WindowsToolchainStatus.missingSdk;
    return WindowsToolchainStatus.ready;
  }

  bool get isReady => status == WindowsToolchainStatus.ready;

  /// `2 installs · Windows SDK 10.0.26100`, dropping what is not there.
  String get countLabel {
    final count = installs.length;
    final sdk = newestSdk;
    return [
      '$count install${count == 1 ? '' : 's'}',
      if (sdk != null) 'SDK ${sdk.displayVersion}',
    ].join(' · ');
  }

  @override
  List<Object?> get props => [installs, sdks];
}

/// Reads `vswhere -format json`.
///
/// [withCppTools] holds the install paths a second `vswhere -requires` call
/// returned, which is how the C++ toolset is detected — the JSON above does not
/// list components.
List<VisualStudioInstall> parseVsWhere(
  String body, {
  Set<String> withCppTools = const {},
}) {
  final decoded = _decodeList(body);
  if (decoded == null) return const [];

  final normalised = {
    for (final path in withCppTools) _normalise(path),
  };

  final installs = <VisualStudioInstall>[];
  for (final entry in decoded.whereType<Map<String, dynamic>>()) {
    final path = entry['installationPath'] as String?;
    if (path == null || path.isEmpty) continue;
    final catalog = entry['catalog'];
    installs.add(VisualStudioInstall(
      displayName:
          entry['displayName'] as String? ?? 'Visual Studio',
      version: entry['installationVersion'] as String? ?? '',
      installPath: path,
      productId: entry['productId'] as String? ?? '',
      isComplete: entry['isComplete'] as bool? ?? true,
      isPrerelease: catalog is Map<String, dynamic>
          ? (catalog['productMilestoneIsPreRelease'] as bool? ?? false)
          : false,
      hasCppTools: normalised.contains(_normalise(path)),
    ));
  }

  // Newest first: that is the one a build picks up.
  installs.sort((a, b) => _compareVersions(b.version, a.version));
  return installs;
}

/// Reads the install paths out of `vswhere -property installationPath`.
List<String> parseVsWherePaths(String output) => [
  for (final line in output.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

/// Reads `KitsRoot10` out of `reg query … /v KitsRoot10`.
String? parseKitsRoot(String output) {
  final pattern = RegExp(r'KitsRoot10\s+REG_[A-Z_]+\s+(.+)$');
  for (final line in output.split('\n')) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final value = match.group(1)!.trim();
    if (value.isNotEmpty) return value;
  }
  return null;
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
  sdks.sort((a, b) => _compareVersions(b.version, a.version));
  return sdks;
}

String _normalise(String path) {
  var value = path.trim().replaceAll('/', r'\');
  while (value.length > 1 && value.endsWith(r'\')) {
    value = value.substring(0, value.length - 1);
  }
  return value.toLowerCase();
}

int _compareVersions(String a, String b) {
  final left = _components(a);
  final right = _components(b);
  for (var i = 0; i < left.length || i < right.length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}

List<int> _components(String version) => [
  for (final part in version.split('.')) int.tryParse(part) ?? 0,
];

List<dynamic>? _decodeList(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is List ? decoded : null;
  } catch (_) {
    return null;
  }
}
