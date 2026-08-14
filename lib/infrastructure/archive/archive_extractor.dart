import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../core/platform/platform_service.dart';
import '../java/archive_format.dart';

/// Unpacks a downloaded archive, whatever container the vendor served.
///
/// Shared by the JDK installer and the Android SDK bootstrap because both hit
/// the same two problems: the format follows the *archive*, never the host — a
/// vendor serves `.zip` to Windows and `.tar.gz` to Linux and macOS — and a Unix
/// tool that comes out of an archive without its execute bit is a tool that does
/// not run.
///
/// Always an external process. `tar` has shipped in Windows since 1803 and reads
/// both zip and gzip, and a pure-Dart unpack of a 200 MB archive is minutes of
/// work on the UI isolate; a separate process costs a frame of nothing.
@lazySingleton
class ArchiveExtractor {
  ArchiveExtractor(this._runner, this._platform);

  final CommandRunner _runner;
  final PlatformService _platform;

  static final Logger _log = Logger('ArchiveExtractor');

  /// Files outside `bin` that a Java or Android tool needs to be executable.
  ///
  /// `jspawnhelper` is the JVM's subprocess launcher and lives in `lib`; without
  /// it the JVM cannot start anything.
  static const _extraExecutables = ['lib/jspawnhelper', 'lib/jexec'];

  /// Unpacks [archive] into [destination], picking the extractor by what the
  /// file's signature bytes say it is.
  ///
  /// Throws a [NetworkFailure] when the download is not an archive at all —
  /// which is what a CDN error page served with a 200 looks like from here — and
  /// a [ProcessFailure] when the extractor itself fails.
  Future<void> extract(File archive, Directory destination) async {
    final format = await detectArchiveFormat(archive);
    _log.info(
      'Unpacking ${p.basename(archive.path)} as ${format.name} '
      '(${_platform.operatingSystem}).',
    );

    final (command, arguments) = switch (format) {
      // bsdtar on Windows reads zip; elsewhere tar does not, so unzip it is.
      ArchiveFormat.zip when _platform.isWindows => (
        'tar',
        ['-xf', archive.path, '-C', destination.path],
      ),
      ArchiveFormat.zip => (
        'unzip',
        ['-q', archive.path, '-d', destination.path],
      ),
      ArchiveFormat.tarGz => (
        'tar',
        ['-xzf', archive.path, '-C', destination.path],
      ),
      ArchiveFormat.tar => (
        'tar',
        ['-xf', archive.path, '-C', destination.path],
      ),
      ArchiveFormat.unknown => throw NetworkFailure(
        'The download is ${format.label}.',
        suggestion: 'The server may have sent an error page instead of the '
            'archive. Try again.',
      ),
    };

    final result = await _runner.run(
      command,
      arguments,
      timeout: const Duration(minutes: 10),
    );
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Could not unpack ${format.label} with `$command`. '
        'Make sure `$command` is installed and on PATH.',
        exitCode: result.exitCode,
        output: result.combinedOutput.trim(),
      );
    }
  }

  /// Puts the executable bit back on every tool under [root].
  ///
  /// `tar` restores modes from the archive and Info-ZIP's `unzip` restores them
  /// from a zip's external attributes, so on a good day this changes nothing. It
  /// is not always a good day: a zip built on Windows carries no Unix modes at
  /// all, and Google's `commandlinetools-linux-*.zip` is one of them — its
  /// `bin/sdkmanager` arrives non-executable.
  ///
  /// Never fatal. The caller's own launch check is what decides whether the
  /// install works; this only removes the most common reason it would not.
  Future<void> restoreExecutableBits(String root) async {
    if (_platform.isWindows) return;

    final targets = executableTargets(root);
    if (targets.isEmpty) return;

    // No shell: a staging path with a space in it must not become two
    // arguments, and there is no glob here that needs expanding.
    final result = await _runner.run(
      'chmod',
      ['+x', ...targets],
      runInShell: false,
      timeout: const Duration(seconds: 30),
    );
    if (!result.isSuccess) {
      _log.warning('chmod +x on $root failed: ${result.combinedOutput.trim()}');
    }
  }

  /// Everything under [root] that has to be executable.
  ///
  /// Every file in `bin`, plus the helpers that live outside it. Missing entries
  /// are simply absent — an older JDK has no `jexec`, and the Android
  /// command-line tools have neither. Split out from the chmod so the selection
  /// can be tested without running a process.
  static List<String> executableTargets(String root) {
    final targets = <String>[];
    final bin = Directory(p.join(root, 'bin'));
    if (bin.existsSync()) {
      for (final entry in bin.listSync()) {
        if (entry is File) targets.add(entry.path);
      }
    }
    for (final relative in _extraExecutables) {
      final file = File(p.join(root, p.joinAll(relative.split('/'))));
      if (file.existsSync()) targets.add(file.path);
    }
    return targets;
  }
}
