import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';

/// Manages the "run at Windows startup" entry via the per-user Run registry
/// key (`HKCU\...\CurrentVersion\Run`).
@lazySingleton
class StartupService {
  StartupService(this._runner);

  final CommandRunner _runner;

  static const String _key =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = 'AndroidSdkManager';

  /// Whether the app is registered to launch at login.
  Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await _runner.run(
        'reg',
        ['query', _key, '/v', _valueName],
        timeout: const Duration(seconds: 10),
      );
      return result.isSuccess && result.stdout.contains(_valueName);
    } catch (_) {
      return false;
    }
  }

  /// Adds or removes the startup entry, pointing at the current executable.
  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows) return;
    if (enabled) {
      final exe = Platform.resolvedExecutable;
      await _runner.run(
        'reg',
        ['add', _key, '/v', _valueName, '/t', 'REG_SZ', '/d', exe, '/f'],
        timeout: const Duration(seconds: 10),
      );
    } else {
      await _runner.run(
        'reg',
        ['delete', _key, '/v', _valueName, '/f'],
        timeout: const Duration(seconds: 10),
      );
    }
  }
}
