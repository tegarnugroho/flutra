import 'package:equatable/equatable.dart';

/// A single Android Virtual Device as reported by `avdmanager list avd`.
class Avd extends Equatable {
  const Avd({
    required this.name,
    this.deviceName,
    this.deviceId,
    this.target,
    this.androidVersion,
    this.apiLevel,
    this.tag,
    this.abi,
    this.path,
    this.sdcard,
    this.isRunning = false,
    this.error,
  });

  final String name;

  /// Human device name, e.g. "Pixel 6".
  final String? deviceName;

  /// avdmanager device id, e.g. "pixel_6".
  final String? deviceId;

  /// Target line, e.g. "Google APIs (Google Inc.)".
  final String? target;

  /// Android version label, e.g. "14.0".
  final String? androidVersion;

  /// Numeric API level, e.g. 34.
  final int? apiLevel;

  /// System image tag, e.g. "google_apis", "google_apis_playstore", "default".
  final String? tag;

  /// ABI, e.g. "x86_64", "arm64-v8a".
  final String? abi;

  /// Absolute path to the `.avd` directory.
  final String? path;

  /// SD card size label, if configured.
  final String? sdcard;

  /// Whether an emulator process is currently running this AVD.
  final bool isRunning;

  /// A parse/load error reported by avdmanager for this entry.
  final String? error;

  Avd copyWith({bool? isRunning}) => Avd(
        name: name,
        deviceName: deviceName,
        deviceId: deviceId,
        target: target,
        androidVersion: androidVersion,
        apiLevel: apiLevel,
        tag: tag,
        abi: abi,
        path: path,
        sdcard: sdcard,
        isRunning: isRunning ?? this.isRunning,
        error: error,
      );

  @override
  List<Object?> get props => [name, path, tag, abi, apiLevel, isRunning];
}
