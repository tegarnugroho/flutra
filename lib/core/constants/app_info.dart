import 'dart:io';

/// Everything the app says about itself, in one place.
///
/// Values that only a build can know arrive through `--dart-define`; in a dev
/// run they are undefined and every consumer shows [unknown] rather than a
/// stale constant that would be wrong the moment it was committed.
class AppInfo {
  const AppInfo._();

  /// What to render for a value the build didn't supply.
  static const String unknown = '—';

  static const String name = 'Flutter SDK Manager';
  static const String author = 'Tegar';
  static const String license = 'MIT License';

  static const String repositoryUrl =
      'https://github.com/tegaranugroho/android_sdk_manager';
  static const String issuesUrl = '$repositoryUrl/issues';
  static const String releaseNotesUrl = '$repositoryUrl/releases';

  // TODO(ci): no CI config exists in this repository yet. When one is added,
  // pass these along with the version so a release build reports itself
  // accurately:
  //   flutter build windows \
  //     --dart-define=APP_VERSION=1.0.4 \
  //     --dart-define=APP_BUILD_NUMBER=4 \
  //     --dart-define=APP_FLUTTER_VERSION=$(flutter --version --machine | ...) \
  //     --dart-define=APP_DART_VERSION=... \
  //     --dart-define=APP_COMMIT=$(git rev-parse --short HEAD) \
  //     --dart-define=APP_CHANNEL=stable

  /// Mirrors `version:` in pubspec.yaml.
  ///
  /// A constant rather than `package_info_plus`: the package isn't a
  /// dependency, and adding one to read two strings is a poor trade. The
  /// define wins when a build supplies it.
  // TODO(version): keep in step with pubspec until the define is wired in CI.
  static const String version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.4',
  );

  static const String buildNumber = String.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: '4',
  );

  static const String channel = String.fromEnvironment(
    'APP_CHANNEL',
    defaultValue: 'stable',
  );

  /// Flutter version this build was compiled with, when a build said so.
  ///
  /// There is no runtime equivalent — the framework doesn't carry its own
  /// version — so without the define the About window falls back to the SDK it
  /// currently manages, which is the same checkout on a developer's machine.
  static const String flutterVersion = String.fromEnvironment(
    'APP_FLUTTER_VERSION',
    defaultValue: unknown,
  );

  static const String _dartVersionDefine = String.fromEnvironment(
    'APP_DART_VERSION',
    defaultValue: unknown,
  );

  /// The Dart the app is running on.
  ///
  /// Unlike the other two this needs no define: the VM reports it, and what it
  /// reports *is* the answer — the runtime is the build.
  static String get dartVersion {
    if (_dartVersionDefine != unknown) return _dartVersionDefine;
    // "3.12.2 (stable) (Tue Jun 9 …) on "windows_x64""
    final match = RegExp(r'^(\d+\.\d+\.\d+\S*)').firstMatch(
      Platform.version,
    );
    return match?.group(1) ?? unknown;
  }

  /// Short commit hash of the source this build came from.
  static const String commit = String.fromEnvironment(
    'APP_COMMIT',
    defaultValue: unknown,
  );

  /// e.g. "Windows x64" — read from the running machine, so it needs no define.
  static String get platformLabel {
    final os = Platform.operatingSystem;
    final name = os.isEmpty
        ? unknown
        : '${os[0].toUpperCase()}${os.substring(1)}';
    // Dart has no direct arch API; the VM's version string carries it.
    final arch = RegExp(
      r'on "\w+?_(\w+)"',
    ).firstMatch(Platform.version)?.group(1);
    return arch == null ? name : '$name $arch';
  }

  /// The copyright year. Stamped at run time so it never goes stale.
  static String get year => DateTime.now().year.toString();

  static String get copyright => '© $year $author — $license';

  /// The block the About window's copy button writes: enough for a bug report,
  /// with unavailable lines left out rather than filled with dashes.
  static String diagnosticBlock() {
    final lines = <String>[
      '$name $version (build $buildNumber)',
      'Channel: $channel · $platformLabel',
      if (flutterVersion != unknown || dartVersion != unknown)
        'Flutter: $flutterVersion · Dart: $dartVersion',
      if (commit != unknown) 'Commit: $commit',
    ];
    return lines.join('\n');
  }
}
