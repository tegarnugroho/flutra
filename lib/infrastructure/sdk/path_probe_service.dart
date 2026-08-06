import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../core/platform/platform_service.dart';

/// What a probe made of a folder the user typed or picked.
class PathProbe {
  const PathProbe({required this.valid, required this.message, this.detail});

  /// Whether the folder looks like what the setting expects.
  ///
  /// A false here is a *warning*, not a veto — the app still saves the
  /// override, because a layout it doesn't recognise may still work.
  final bool valid;

  /// One line for under the input.
  final String message;

  /// Extra fact worth surfacing, e.g. the version found.
  final String? detail;
}

/// Checks whether a folder holds what a setting says it should.
///
/// Shape checks are plain file-system reads; the Flutter version needs the tool
/// itself, so it goes through the shared [CommandRunner] like every other
/// external call.
@lazySingleton
class PathProbeService {
  PathProbeService(this._runner, this._platform);

  final CommandRunner _runner;
  final PlatformService _platform;

  /// An Android SDK root holds the tool folders sdkmanager creates.
  Future<PathProbe> probeAndroidSdk(String path) async {
    final dir = Directory(path.trim());
    if (path.trim().isEmpty || !dir.existsSync()) {
      return const PathProbe(valid: false, message: 'Folder does not exist');
    }
    const markers = ['platform-tools', 'cmdline-tools', 'build-tools'];
    final found = markers.where(
      (m) => Directory(p.join(dir.path, m)).existsSync(),
    );
    if (found.isEmpty) {
      return const PathProbe(
        valid: false,
        message: 'Folder does not look like an Android SDK — save anyway?',
      );
    }
    return PathProbe(
      valid: true,
      message: 'Valid Android SDK',
      detail: found.join(' · '),
    );
  }

  /// A Flutter checkout has `bin/flutter`; the version comes from running it.
  Future<PathProbe> probeFlutterSdk(String path) async {
    final root = path.trim();
    if (root.isEmpty || !Directory(root).existsSync()) {
      return const PathProbe(valid: false, message: 'Folder does not exist');
    }
    final exe = p.join(root, 'bin', _platform.flutterExecutable);
    if (!File(exe).existsSync()) {
      return const PathProbe(
        valid: false,
        message: 'No bin/flutter here — save anyway?',
      );
    }
    final version = await _flutterVersion(exe);
    return PathProbe(
      valid: true,
      message: version == null
          ? 'Valid Flutter checkout'
          : 'Valid Flutter checkout · $version detected',
    );
  }

  Future<String?> _flutterVersion(String executable) async {
    try {
      final result = await _runner.run(
        executable,
        ['--version'],
        timeout: const Duration(seconds: 25),
      );
      // First line reads "Flutter 3.44.8 • channel stable • ...".
      final match = RegExp(
        r'Flutter\s+(\d+\.\d+\.\d+\S*)',
      ).firstMatch(result.stdout);
      return match?.group(1);
    } catch (_) {
      // A checkout that won't run still has the right shape; report neither a
      // version nor a failure.
      return null;
    }
  }
}
