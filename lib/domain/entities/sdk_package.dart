import 'package:equatable/equatable.dart';

/// Installation state of an SDK package from `sdkmanager --list`.
enum PackageState { installed, available, updatable }

/// Coarse grouping derived from a package's path prefix.
enum PackageCategory {
  platformTools,
  buildTools,
  platforms,
  systemImages,
  emulator,
  cmdlineTools,
  sources,
  ndk,
  extras,
  other,
}

extension PackageCategoryInfo on PackageCategory {
  String get label => switch (this) {
        PackageCategory.platformTools => 'Platform Tools',
        PackageCategory.buildTools => 'Build Tools',
        PackageCategory.platforms => 'Platforms',
        PackageCategory.systemImages => 'System Images',
        PackageCategory.emulator => 'Emulator',
        PackageCategory.cmdlineTools => 'Command-line Tools',
        PackageCategory.sources => 'Sources',
        PackageCategory.ndk => 'NDK',
        PackageCategory.extras => 'Extras',
        PackageCategory.other => 'Other',
      };
}

/// A single SDK component as reported by `sdkmanager`.
class SdkPackage extends Equatable {
  const SdkPackage({
    required this.path,
    required this.description,
    required this.state,
    this.installedVersion,
    this.availableVersion,
    this.location,
  });

  /// The sdkmanager path/id, e.g. "system-images;android-34;google_apis;x86_64".
  final String path;

  final String description;
  final PackageState state;

  /// Version currently installed (for installed/updatable).
  final String? installedVersion;

  /// Version available to install/update to.
  final String? availableVersion;

  /// Install location relative to the SDK root (installed only).
  final String? location;

  bool get isInstalled =>
      state == PackageState.installed || state == PackageState.updatable;

  bool get hasUpdate => state == PackageState.updatable;

  /// The version most relevant to show for this row.
  String? get displayVersion =>
      installedVersion ?? availableVersion;

  PackageCategory get category {
    final head = path.split(';').first;
    return switch (head) {
      'platform-tools' => PackageCategory.platformTools,
      'build-tools' => PackageCategory.buildTools,
      'platforms' => PackageCategory.platforms,
      'system-images' => PackageCategory.systemImages,
      'emulator' => PackageCategory.emulator,
      'cmdline-tools' || 'tools' => PackageCategory.cmdlineTools,
      'sources' => PackageCategory.sources,
      'ndk' || 'ndk-bundle' => PackageCategory.ndk,
      'extras' || 'add-ons' => PackageCategory.extras,
      _ => PackageCategory.other,
    };
  }

  SdkPackage copyWith({
    PackageState? state,
    String? installedVersion,
    String? availableVersion,
    String? location,
  }) {
    return SdkPackage(
      path: path,
      description: description,
      state: state ?? this.state,
      installedVersion: installedVersion ?? this.installedVersion,
      availableVersion: availableVersion ?? this.availableVersion,
      location: location ?? this.location,
    );
  }

  @override
  List<Object?> get props =>
      [path, state, installedVersion, availableVersion];
}
