import 'package:equatable/equatable.dart';

/// High-level installation state of a tool or component, as shown on the
/// dashboard with ✔ / ❌ / ⚠ indicators.
enum ToolState {
  /// Detected and healthy.
  installed,

  /// Not found on the system.
  missing,

  /// Installed, but an update is available.
  needsUpdate,

  /// Detection is still running.
  checking,

  /// Detection failed for an unexpected reason.
  error,
}

/// The category of tool a [ToolStatus] describes. Drives icons and grouping.
enum ToolKind { sdk, java, flutter, emulator, adb }

/// The detected status of a single tool on the dashboard.
class ToolStatus extends Equatable {
  const ToolStatus({
    required this.kind,
    required this.state,
    this.version,
    this.path,
    this.detail,
    this.latestVersion,
  });

  /// A placeholder status used before detection has run.
  factory ToolStatus.checking(ToolKind kind) =>
      ToolStatus(kind: kind, state: ToolState.checking);

  final ToolKind kind;
  final ToolState state;

  /// Installed version string, if known (e.g. "35.0.0", "17.0.10").
  final String? version;

  /// Resolved absolute path to the tool / SDK root.
  final String? path;

  /// Extra human-readable context (e.g. "3 platforms installed").
  final String? detail;

  /// Newest available version when [state] is [ToolState.needsUpdate].
  final String? latestVersion;

  bool get isInstalled =>
      state == ToolState.installed || state == ToolState.needsUpdate;

  String get displayName => switch (kind) {
        ToolKind.sdk => 'Android SDK',
        ToolKind.java => 'Java (JDK)',
        ToolKind.flutter => 'Flutter',
        ToolKind.emulator => 'Emulator',
        ToolKind.adb => 'ADB (platform tools)',
      };

  ToolStatus copyWith({
    ToolState? state,
    String? version,
    String? path,
    String? detail,
    String? latestVersion,
  }) {
    return ToolStatus(
      kind: kind,
      state: state ?? this.state,
      version: version ?? this.version,
      path: path ?? this.path,
      detail: detail ?? this.detail,
      latestVersion: latestVersion ?? this.latestVersion,
    );
  }

  @override
  List<Object?> get props =>
      [kind, state, version, path, detail, latestVersion];
}
