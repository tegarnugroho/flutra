import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';

/// What the host machine can spare, used to size emulator presets sensibly.
///
/// Every field is nullable on purpose: a value the app could not measure is
/// absent, never guessed. Callers drop the hint and the cap rather than invent
/// a number.
class HostInfo {
  const HostInfo({required this.cores, this.totalRamMb});

  /// Logical processors. Always known — [Platform.numberOfProcessors].
  final int cores;

  /// Physical RAM in MB, or null when it could not be read.
  final int? totalRamMb;

  int? get totalRamGb => totalRamMb == null ? null : totalRamMb! ~/ 1024;
}

/// Reads host capacity: CPU count, physical RAM, and free space on a drive.
///
/// Follows the same shape as [ProcessService]: PowerShell through the shared
/// [CommandRunner] rather than FFI, so there is one way system facts are read.
@lazySingleton
class HostInfoService {
  HostInfoService(this._runner);

  final CommandRunner _runner;

  HostInfo? _cached;

  /// Host capacity, measured once per session — it cannot change while the app
  /// runs, and the RAM probe costs a PowerShell launch.
  Future<HostInfo> info() async {
    final cached = _cached;
    if (cached != null) return cached;
    final info = HostInfo(
      cores: Platform.numberOfProcessors,
      totalRamMb: await _totalRamMb(),
    );
    _cached = info;
    return info;
  }

  Future<int?> _totalRamMb() async {
    if (!Platform.isWindows) return null;
    const script = r'(Get-CimInstance Win32_ComputerSystem)'
        r'.TotalPhysicalMemory';
    final bytes = await _readNumber(script);
    return bytes == null ? null : bytes ~/ (1024 * 1024);
  }

  /// Free space in MB on the volume holding [path], or null when unknown.
  Future<int?> freeSpaceMb(String path) async {
    if (!Platform.isWindows) return null;
    // Ask about the volume the path sits on rather than a hard-coded C:, since
    // an AVD home can be redirected anywhere by ANDROID_AVD_HOME.
    final drive = _driveOf(path);
    if (drive == null) return null;
    final script =
        "(Get-PSDrive -Name '$drive' -ErrorAction SilentlyContinue).Free";
    final bytes = await _readNumber(script);
    return bytes == null ? null : bytes ~/ (1024 * 1024);
  }

  /// The drive letter of an absolute Windows path, e.g. "E" for `E:\\avd`.
  static String? _driveOf(String path) {
    if (path.length < 2 || path[1] != ':') return null;
    final letter = path[0].toUpperCase();
    return RegExp(r'^[A-Z]$').hasMatch(letter) ? letter : null;
  }

  Future<int?> _readNumber(String script) async {
    try {
      final result = await _runner.run(
        'powershell',
        ['-NoProfile', '-Command', script],
        timeout: const Duration(seconds: 10),
      );
      return int.tryParse(result.stdout.trim());
    } catch (_) {
      // An unreadable host fact is not an error worth surfacing — the UI just
      // stops showing that hint.
      return null;
    }
  }
}
