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

  static String? _str(Object? v) =>
      (v is String && v.trim().isNotEmpty) ? v : null;

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
      ];
}
