import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Discovers the Android SDK root and resolves the paths of the individual
/// command-line tools inside it.
///
/// Resolution order for the SDK root:
///  1. An explicit override set via [overrideSdkRoot] (from settings).
///  2. `ANDROID_HOME` / `ANDROID_SDK_ROOT` environment variables.
///  3. Well-known default locations (including an Android Studio install).
@lazySingleton
class SdkLocator {
  SdkLocator();

  String? _override;

  /// Sets a user-configured SDK root, taking precedence over auto-detection.
  set overrideSdkRoot(String? path) => _override = path;

  /// The resolved SDK root directory, or null if none can be found.
  String? get sdkRoot {
    for (final candidate in _candidateRoots()) {
      if (candidate != null && _looksLikeSdk(candidate)) return candidate;
    }
    return null;
  }

  Iterable<String?> _candidateRoots() sync* {
    yield _override;
    yield Platform.environment['ANDROID_HOME'];
    yield Platform.environment['ANDROID_SDK_ROOT'];

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      yield p.join(localAppData, 'Android', 'Sdk');
    }
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      yield p.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk');
      yield p.join(userProfile, 'Android', 'Sdk');
    }
  }

  bool _looksLikeSdk(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return false;
    // A usable SDK has at least one of these well-known sub-directories.
    const markers = ['cmdline-tools', 'platform-tools', 'tools', 'emulator'];
    return markers.any((m) => Directory(p.join(root, m)).existsSync());
  }

  // ---- Tool path resolution ------------------------------------------------

  String _exe(String name) => Platform.isWindows ? '$name.exe' : name;
  String _bat(String name) => Platform.isWindows ? '$name.bat' : name;

  /// Path to `sdkmanager`, searching both new and legacy layouts.
  String? get sdkManager => _firstExisting([
        if (sdkRoot != null) ...[
          p.join(sdkRoot!, 'cmdline-tools', 'latest', 'bin', _bat('sdkmanager')),
          p.join(sdkRoot!, 'cmdline-tools', 'bin', _bat('sdkmanager')),
          p.join(sdkRoot!, 'tools', 'bin', _bat('sdkmanager')),
        ],
      ]);

  /// Path to `avdmanager`.
  String? get avdManager => _firstExisting([
        if (sdkRoot != null) ...[
          p.join(sdkRoot!, 'cmdline-tools', 'latest', 'bin', _bat('avdmanager')),
          p.join(sdkRoot!, 'cmdline-tools', 'bin', _bat('avdmanager')),
          p.join(sdkRoot!, 'tools', 'bin', _bat('avdmanager')),
        ],
      ]);

  /// Path to `adb` from platform-tools.
  String? get adb => _firstExisting([
        if (sdkRoot != null)
          p.join(sdkRoot!, 'platform-tools', _exe('adb')),
      ]);

  /// Path to the `emulator` binary.
  String? get emulator => _firstExisting([
        if (sdkRoot != null) p.join(sdkRoot!, 'emulator', _exe('emulator')),
      ]);

  /// The `build-tools` directory (holds one sub-dir per installed version).
  String? get buildToolsDir =>
      sdkRoot == null ? null : p.join(sdkRoot!, 'build-tools');

  /// The `platforms` directory (holds one sub-dir per installed API level).
  String? get platformsDir =>
      sdkRoot == null ? null : p.join(sdkRoot!, 'platforms');

  /// Returns the highest installed build-tools version, or null.
  String? get latestBuildToolsVersion {
    final versions = installedBuildToolsVersions;
    return versions.isEmpty ? null : versions.last;
  }

  /// All installed build-tools versions, sorted ascending.
  List<String> get installedBuildToolsVersions {
    final dir = buildToolsDir;
    if (dir == null || !Directory(dir).existsSync()) return const [];
    final versions = Directory(dir)
        .listSync()
        .whereType<Directory>()
        .map((d) => p.basename(d.path))
        .toList()
      ..sort(_compareVersions);
    return versions;
  }

  /// Installed platform API levels (e.g. ["android-34", "android-35"]).
  List<String> get installedPlatforms {
    final dir = platformsDir;
    if (dir == null || !Directory(dir).existsSync()) return const [];
    return Directory(dir)
        .listSync()
        .whereType<Directory>()
        .map((d) => p.basename(d.path))
        .toList()
      ..sort();
  }

  String? _firstExisting(List<String> candidates) {
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// Compares dotted version strings numerically ("9.0.0" < "10.0.0").
  static int _compareVersions(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final na = int.tryParse(pa[i]) ?? 0;
      final nb = int.tryParse(pb[i]) ?? 0;
      if (na != nb) return na.compareTo(nb);
    }
    return pa.length.compareTo(pb.length);
  }
}
