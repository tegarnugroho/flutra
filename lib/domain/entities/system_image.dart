import 'package:equatable/equatable.dart';

/// An installed Android system image usable as the basis for an AVD.
///
/// Derived from the `system-images` directory of the SDK; its [packagePath] is
/// the identifier accepted by `avdmanager create avd -k`.
class SystemImage extends Equatable {
  const SystemImage({
    required this.packagePath,
    required this.platform,
    required this.apiLevel,
    required this.tag,
    required this.abi,
  });

  /// e.g. "system-images;android-34;google_apis;x86_64".
  final String packagePath;

  /// e.g. "android-34".
  final String platform;

  /// Numeric API level parsed from [platform].
  final int apiLevel;

  /// e.g. "google_apis", "google_apis_playstore", "default", "android-wear".
  final String tag;

  /// e.g. "x86_64", "arm64-v8a".
  final String abi;

  /// Friendly tag label for display.
  String get tagLabel => switch (tag) {
        'default' => 'AOSP (no Google APIs)',
        'google_apis' => 'Google APIs',
        'google_apis_playstore' => 'Google Play',
        'android-wear' => 'Wear OS',
        'android-tv' => 'Android TV',
        'google_apis_playstore_ps16k' => 'Google Play (16 KB)',
        _ => tag,
      };

  @override
  List<Object?> get props => [packagePath];
}
