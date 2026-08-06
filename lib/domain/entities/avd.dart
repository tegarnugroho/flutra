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

  /// The system image tag in the words a developer uses for it.
  ///
  /// Null when the AVD reports no tag at all — the meta line then drops the
  /// segment rather than printing "unknown".
  String? get displayImageType => tag == null ? null : humanizeImageTag(tag!);

  /// What kind of device this AVD emulates, for the tile's icon.
  AvdDeviceKind get kind => avdDeviceKind(deviceId, deviceName, name);

  @override
  List<Object?> get props => [name, path, tag, abi, apiLevel, isRunning];
}

/// The device families the emulator list tells apart.
enum AvdDeviceKind { phone, tablet, tv, wear }

/// Reads the device family out of whatever the AVD names itself.
///
/// avdmanager reports no explicit family, so this is a read of the device id
/// first (`pixel_tablet`, `tv_1080p`, `wear_round`) and only then of the names,
/// which the user picked and may say anything.
AvdDeviceKind avdDeviceKind(String? deviceId, String? deviceName, String name) {
  final haystack = [
    deviceId,
    deviceName,
    name,
  ].whereType<String>().map((s) => s.toLowerCase()).join(' ');

  // Wear and TV first: "Android TV (1080p)" also contains none of the others,
  // but a watch face image can carry a phone-shaped id.
  if (haystack.contains('wear') || haystack.contains('watch')) {
    return AvdDeviceKind.wear;
  }
  if (RegExp(r'\btv\b|television|_tv|tv_').hasMatch(haystack)) {
    return AvdDeviceKind.tv;
  }
  if (haystack.contains('tablet') ||
      haystack.contains('foldable') ||
      // The Nexus 7/9/10 and Pixel C are tablets that say so nowhere else.
      // Written with an optional space or underscore because the id and the
      // display name spell the same device differently ("nexus_10", "Nexus 10").
      RegExp(r'nexus[ _]?(7|9|10)\b|pixel[ _]?c\b').hasMatch(haystack)) {
    return AvdDeviceKind.tablet;
  }
  return AvdDeviceKind.phone;
}

/// `google_apis_playstore` → `Play Store`.
///
/// The raw tag stays available for the tooltip: these are the strings that
/// appear in `sdkmanager` package paths, so the exact value still matters when
/// something has to be looked up.
String humanizeImageTag(String tag) {
  return switch (tag.trim().toLowerCase()) {
    'google_apis_playstore' || 'playstore' => 'Play Store',
    'google_apis' => 'Google APIs',
    'default' || '' => 'AOSP',
    'android-tv' || 'google_tv' => 'Android TV',
    'android-wear' || 'android-wear-cn' => 'Wear OS',
    'aosp_atd' || 'google_atd' => 'ATD',
    // An unmapped tag is shown as it came: inventing a label for a future
    // image type would hide which one it is.
    final other => other,
  };
}
