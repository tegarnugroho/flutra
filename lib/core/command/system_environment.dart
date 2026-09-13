import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Desktop launchers do not necessarily inherit the user's terminal PATH.
/// Read the login shell once before SDK discovery and command execution.
class SystemEnvironment {
  static Map<String, String> values = Map.of(Platform.environment);

  static Future<void> initialize() async {
    if (Platform.isWindows) return;
    Process? process;
    try {
      process = await Process.start(
        Platform.environment['SHELL'] ?? '/bin/sh',
        ['-ilc', r"printf '\000FLUTRA_ENV\000'; /usr/bin/env -0"],
      );
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      await process.stdin.close();
      await (() async {
        final code = await process!.exitCode;
        final data = await output;
        await errors;
        if (code == 0) values = {...values, ...parse(data)};
      })().timeout(const Duration(seconds: 5));
    } on Exception {
      // A broken or interactive shell profile must not prevent app startup.
    } finally {
      process?.kill();
    }
  }

  /// NUL framing tolerates shell banners, spaces, newlines and '=' in values.
  static Map<String, String> parse(String output) {
    const marker = '\x00FLUTRA_ENV\x00';
    final start = output.indexOf(marker);
    if (start < 0) return {};
    final result = <String, String>{};
    for (final entry in output.substring(start + marker.length).split('\x00')) {
      final separator = entry.indexOf('=');
      if (separator > 0) {
        result[entry.substring(0, separator)] = entry.substring(separator + 1);
      }
    }
    return result;
  }
}
