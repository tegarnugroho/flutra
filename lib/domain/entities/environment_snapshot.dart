import 'package:equatable/equatable.dart';

import 'tool_status.dart';

/// Aggregate view of the whole toolchain, rendered by the dashboard.
class EnvironmentSnapshot extends Equatable {
  const EnvironmentSnapshot({
    required this.sdk,
    required this.java,
    required this.flutter,
    required this.emulator,
    required this.adb,
    required this.sdkPath,
    required this.javaPath,
    required this.flutterPath,
    required this.platformToolsVersion,
    required this.buildToolsVersion,
    required this.emulatorVersion,
  });

  final ToolStatus sdk;
  final ToolStatus java;
  final ToolStatus flutter;
  final ToolStatus emulator;
  final ToolStatus adb;

  final String? sdkPath;
  final String? javaPath;
  final String? flutterPath;
  final String? platformToolsVersion;
  final String? buildToolsVersion;
  final String? emulatorVersion;

  List<ToolStatus> get all => [sdk, java, flutter, emulator, adb];

  /// True when every core tool is at least installed (updates aside).
  bool get isReady => all.every((t) => t.isInstalled);

  @override
  List<Object?> get props => [
        sdk,
        java,
        flutter,
        emulator,
        adb,
        sdkPath,
        javaPath,
        flutterPath,
        platformToolsVersion,
        buildToolsVersion,
        emulatorVersion,
      ];
}
