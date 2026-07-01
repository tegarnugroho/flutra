import 'package:equatable/equatable.dart';

/// Connection state of an adb device.
enum DeviceState { device, offline, unauthorized, noPermissions, bootloader, unknown }

extension DeviceStateInfo on DeviceState {
  String get label => switch (this) {
        DeviceState.device => 'Online',
        DeviceState.offline => 'Offline',
        DeviceState.unauthorized => 'Unauthorized',
        DeviceState.noPermissions => 'No permissions',
        DeviceState.bootloader => 'Bootloader',
        DeviceState.unknown => 'Unknown',
      };

  /// Only fully-online devices accept shell/install/screenshot actions.
  bool get isOnline => this == DeviceState.device;
}

/// Where to reboot a device to.
enum RebootTarget { system, bootloader, recovery }

/// A device or emulator reported by `adb devices -l`, enriched with properties.
class Device extends Equatable {
  const Device({
    required this.serial,
    required this.state,
    this.model,
    this.product,
    this.transportId,
    this.manufacturer,
    this.androidRelease,
    this.sdkInt,
    this.batteryLevel,
    this.platform,
    this.supportsAdb = true,
  });

  final String serial;
  final DeviceState state;
  final String? model;
  final String? product;
  final String? transportId;
  final String? manufacturer;

  /// Flutter target platform, e.g. "android-arm64", "windows-x64",
  /// "web-javascript". Null for adb-sourced Android devices.
  final String? platform;

  /// Whether adb actions (shell, screenshot, reboot, install) apply. False for
  /// non-Android Flutter targets such as Windows desktop or a web browser.
  final bool supportsAdb;

  /// Android version string, e.g. "14".
  final String? androidRelease;

  /// API level, e.g. 34.
  final int? sdkInt;

  /// Battery percentage 0–100, if available.
  final int? batteryLevel;

  bool get isEmulator => serial.startsWith('emulator-');

  /// True for network (adb connect) devices — the only ones that can be
  /// meaningfully disconnected.
  bool get isNetwork => serial.contains(':');

  String get displayName {
    if (model != null && model!.isNotEmpty) {
      return model!.replaceAll('_', ' ');
    }
    return serial;
  }

  /// Friendly platform label for non-adb (Flutter) devices.
  String? get platformLabel {
    final plat = platform;
    if (plat == null) return null;
    if (plat.startsWith('android')) return 'Android';
    if (plat.startsWith('windows')) return 'Windows';
    if (plat.startsWith('darwin') || plat.startsWith('macos')) return 'macOS';
    if (plat.startsWith('linux')) return 'Linux';
    if (plat.startsWith('web')) return 'Web';
    if (plat.startsWith('ios')) return 'iOS';
    return plat;
  }

  Device copyWith({
    String? manufacturer,
    String? androidRelease,
    int? sdkInt,
    int? batteryLevel,
  }) {
    return Device(
      serial: serial,
      state: state,
      model: model,
      product: product,
      transportId: transportId,
      manufacturer: manufacturer ?? this.manufacturer,
      androidRelease: androidRelease ?? this.androidRelease,
      sdkInt: sdkInt ?? this.sdkInt,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      platform: platform,
      supportsAdb: supportsAdb,
    );
  }

  @override
  List<Object?> get props =>
      [serial, state, model, androidRelease, sdkInt, batteryLevel, platform];
}
