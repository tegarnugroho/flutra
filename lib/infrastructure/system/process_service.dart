import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';

/// System process utilities.
@lazySingleton
class ProcessService {
  ProcessService(this._runner);

  final CommandRunner _runner;

  /// Force-kills every running Flutter/Dart process and returns the count that
  /// was found and terminated. Uses PowerShell enumeration (accurate even when
  /// `taskkill` would silently fail on access-denied). Windows only.
  Future<int> stopFlutterAndDart() async {
    if (!Platform.isWindows) return 0;
    const script = r"$names=@('dart.exe','dartaotruntime.exe','dartvm.exe',"
        r"'flutter_tester.exe'); "
        r"$procs=@(Get-CimInstance Win32_Process | "
        r"Where-Object { $names -contains $_.Name }); "
        r"foreach($p in $procs){ try{ Stop-Process -Id $p.ProcessId -Force "
        r"-ErrorAction SilentlyContinue }catch{} } "
        r"Write-Output ('KILLED=' + $procs.Count)";
    try {
      final result = await _runner.run(
        'powershell',
        ['-NoProfile', '-Command', script],
        timeout: const Duration(seconds: 20),
      );
      final match = RegExp(r'KILLED=(\d+)').firstMatch(result.stdout);
      return match == null ? 0 : int.parse(match.group(1)!);
    } catch (_) {
      return 0;
    }
  }
}
