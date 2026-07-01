import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';

/// System process utilities.
@lazySingleton
class ProcessService {
  ProcessService(this._runner);

  final CommandRunner _runner;

  /// Image names covering the Flutter/Dart toolchain (the `flutter` command
  /// itself runs as dart.exe).
  static const List<String> _images = [
    'dart.exe',
    'dartaotruntime.exe',
    'dartvm.exe',
    'flutter_tester.exe',
  ];

  /// Force-kills every running Flutter/Dart process. Returns the number of
  /// processes terminated. Windows only.
  Future<int> stopFlutterAndDart() async {
    if (!Platform.isWindows) return 0;
    var killed = 0;
    for (final image in _images) {
      try {
        final result = await _runner.run(
          'taskkill',
          ['/F', '/IM', image],
          timeout: const Duration(seconds: 10),
        );
        // taskkill prints one "SUCCESS:" line per terminated PID.
        killed += 'SUCCESS:'.allMatches(result.stdout).length;
      } catch (_) {
        // ignore (image not running / not found)
      }
    }
    return killed;
  }
}
