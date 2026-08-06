import 'package:equatable/equatable.dart';
import 'package:fluent_ui/fluent_ui.dart' show ThemeMode;

/// Persisted application preferences.
class AppSettings extends Equatable {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.androidSdkPath,
    this.flutterSdkPath,
    this.runAtStartup = false,
    this.closeToTray = true,
    this.developerMode = false,
    this.sidebarCollapsed = false,
    this.windowX,
    this.windowY,
    this.windowWidth,
    this.windowHeight,
    this.doctorTimings = const {},
  });

  final ThemeMode themeMode;

  /// User override for the Android SDK root (null = auto-detect).
  final String? androidSdkPath;

  /// User override for the Flutter SDK root (null = use PATH).
  final String? flutterSdkPath;

  final bool runAtStartup;

  /// Hide to the system tray on window close instead of quitting.
  final bool closeToTray;

  /// Reveals developer tools (e.g. the request-log viewer).
  final bool developerMode;

  /// Whether the navigation pane is pinned to its icon rail.
  ///
  /// The user's choice only — the narrow-window rule in the shell forces the
  /// rail without overwriting this, so widening restores what they picked.
  final bool sidebarCollapsed;

  /// Last main-window bounds, restored on next launch.
  final double? windowX;
  final double? windowY;
  final double? windowWidth;
  final double? windowHeight;

  /// How long each `flutter doctor` check took on the last successful run, in
  /// milliseconds, keyed by check name. Drives the time-weighted progress bar.
  final Map<String, int> doctorTimings;

  bool get hasWindowBounds =>
      windowX != null &&
      windowY != null &&
      windowWidth != null &&
      windowHeight != null;

  static String? _str(Object? v) =>
      (v is String && v.trim().isNotEmpty) ? v : null;

  static Map<String, int> _timings(Object? v) {
    if (v is! Map) return const {};
    return {
      for (final entry in v.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).round(),
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: switch (json['themeMode']) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      androidSdkPath: _str(json['androidSdkPath']),
      flutterSdkPath: _str(json['flutterSdkPath']),
      runAtStartup: json['runAtStartup'] as bool? ?? false,
      closeToTray: json['closeToTray'] as bool? ?? true,
      developerMode: json['developerMode'] as bool? ?? false,
      sidebarCollapsed: json['sidebarCollapsed'] as bool? ?? false,
      windowX: (json['windowX'] as num?)?.toDouble(),
      windowY: (json['windowY'] as num?)?.toDouble(),
      windowWidth: (json['windowWidth'] as num?)?.toDouble(),
      windowHeight: (json['windowHeight'] as num?)?.toDouble(),
      doctorTimings: _timings(json['doctorTimings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': switch (themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.system => 'system',
          ThemeMode.dark => 'dark',
        },
        'androidSdkPath': androidSdkPath,
        'flutterSdkPath': flutterSdkPath,
        'runAtStartup': runAtStartup,
        'closeToTray': closeToTray,
        'developerMode': developerMode,
        'sidebarCollapsed': sidebarCollapsed,
        'windowX': windowX,
        'windowY': windowY,
        'windowWidth': windowWidth,
        'windowHeight': windowHeight,
        'doctorTimings': doctorTimings,
      };

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? androidSdkPath,
    bool clearAndroidSdkPath = false,
    String? flutterSdkPath,
    bool clearFlutterSdkPath = false,
    bool? runAtStartup,
    bool? closeToTray,
    bool? developerMode,
    bool? sidebarCollapsed,
    double? windowX,
    double? windowY,
    double? windowWidth,
    double? windowHeight,
    Map<String, int>? doctorTimings,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      androidSdkPath: clearAndroidSdkPath
          ? null
          : (androidSdkPath ?? this.androidSdkPath),
      flutterSdkPath: clearFlutterSdkPath
          ? null
          : (flutterSdkPath ?? this.flutterSdkPath),
      runAtStartup: runAtStartup ?? this.runAtStartup,
      closeToTray: closeToTray ?? this.closeToTray,
      developerMode: developerMode ?? this.developerMode,
      sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
      doctorTimings: doctorTimings ?? this.doctorTimings,
    );
  }

  @override
  List<Object?> get props => [
        themeMode,
        androidSdkPath,
        flutterSdkPath,
        runAtStartup,
        closeToTray,
        developerMode,
        sidebarCollapsed,
        windowX,
        windowY,
        windowWidth,
        windowHeight,
        doctorTimings,
      ];
}
