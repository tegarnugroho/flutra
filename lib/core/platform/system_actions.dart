import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../command/command_runner.dart';
import 'env_persistence.dart';
import 'platform_service.dart';

/// The OS-specific *actions* — killing a process tree, persisting an
/// environment variable, opening a folder or a link, asking for elevation.
///
/// Split from [PlatformService] because that one answers questions about paths
/// with no dependencies at all, which is what lets static helpers and a disk
/// scan use it. These need a [CommandRunner], so they live behind their own
/// injected service rather than dragging that dependency into every path
/// lookup.
abstract class SystemActions {
  /// Ends [pid] and everything it spawned.
  ///
  /// sdkmanager and the licence prompt both run a java child that outlives a
  /// plain kill, which is why this is not just `Process.kill`.
  Future<void> killProcessTree(int pid);

  /// Persists [name] so processes started later see it.
  Future<EnvPersistResult> persistUserEnvVar(String name, String value);

  /// Appends [directory] to the user's PATH, if it is not already on it.
  Future<EnvPersistResult> appendToUserPath(String directory);

  /// The user-level PATH as it stands right now, in the platform's own format.
  ///
  /// Read live rather than from [Platform.environment], which is the snapshot
  /// this process inherited at launch — it never shows what [appendToUserPath]
  /// just wrote. Empty when it cannot be read.
  Future<String> readUserPath();

  /// Shows [path] in the system file manager.
  Future<void> revealInFileManager(String path);

  /// Wraps [command] so the OS asks for elevation with its own dialog.
  ///
  /// Returns null when this platform has no way to ask, in which case the
  /// caller shows the command to run by hand instead. The app never reads,
  /// stores or forwards a password on any platform — every one of these hands
  /// off to a system prompt.
  (String, List<String>)? elevated(String command);
}

/// Windows: `taskkill`, `setx`, PowerShell for PATH, `explorer /select,`.
///
/// Byte-for-byte the commands the app already ran; this only moves them.
class WindowsSystemActions implements SystemActions {
  WindowsSystemActions(this._runner);

  final CommandRunner _runner;
  static final Logger _log = Logger('WindowsSystemActions');

  @override
  Future<void> killProcessTree(int pid) async {
    try {
      await _runner.run('taskkill', ['/T', '/F', '/PID', '$pid'],
          timeout: const Duration(seconds: 15));
    } catch (e) {
      _log.fine('taskkill on $pid failed: $e');
    }
  }

  @override
  Future<EnvPersistResult> persistUserEnvVar(String name, String value) async {
    final result = await _runner.run('setx', [name, value],
        timeout: const Duration(seconds: 30));
    if (!result.isSuccess) {
      return EnvPersistResult.failed(
          'Could not save $name (${result.combinedOutput.trim()}).');
    }
    return const EnvPersistResult(
      success: true,
      restartRequired: true,
      note: 'Saved. Terminals already open keep the old value until they are '
          'reopened.',
    );
  }

  @override
  Future<EnvPersistResult> appendToUserPath(String directory) async {
    // Read-modify-write through PowerShell rather than `setx PATH`: setx
    // truncates at 1024 characters and would silently destroy a long PATH.
    final script = "\$b='$directory'; "
        "\$p=[Environment]::GetEnvironmentVariable('Path','User'); "
        "if(\$p -notlike \"*\$b*\"){"
        "[Environment]::SetEnvironmentVariable('Path', "
        "(\$p.TrimEnd(';') + ';' + \$b), 'User')}";
    final result = await _runner.run(
      'powershell',
      ['-NoProfile', '-Command', script],
      timeout: const Duration(seconds: 30),
    );
    if (!result.isSuccess) {
      return EnvPersistResult.failed(
          'Could not update PATH. Add "$directory" to it by hand.');
    }
    return const EnvPersistResult(
      success: true,
      restartRequired: true,
      note: 'PATH updated. New terminals — and this app after a restart — will '
          'find it.',
    );
  }

  @override
  Future<String> readUserPath() async {
    try {
      final result = await _runner.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "[Environment]::GetEnvironmentVariable('Path','User')",
        ],
        timeout: const Duration(seconds: 20),
      );
      return result.isSuccess ? result.stdout.trim() : '';
    } catch (e) {
      _log.fine('could not read the user PATH: $e');
      return '';
    }
  }

  @override
  Future<void> revealInFileManager(String path) async {
    // `explorer` returns a non-zero exit code even when it works, so its
    // result is deliberately not checked.
    try {
      await Process.start('explorer', [path], mode: ProcessStartMode.detached);
    } catch (e) {
      _log.warning('could not open $path: $e');
    }
  }

  @override
  (String, List<String>)? elevated(String command) => (
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "Start-Process -FilePath 'cmd' -Verb RunAs -ArgumentList '/c','$command'",
        ],
      );
}

/// Linux and macOS share the file the exports live in; only how a GUI session
/// picks them up, and how elevation is asked for, differ.
abstract class _UnixSystemActions implements SystemActions {
  _UnixSystemActions(this.runner, this.platform);

  final CommandRunner runner;
  final PlatformService platform;

  static final Logger _log = Logger('UnixSystemActions');

  /// The rc files a login shell reads, most important first.
  List<String> get rcFiles;

  String? get home => Platform.environment['HOME'];

  /// `~/.config/flutra/env.sh`.
  String? get envScriptPath {
    final base = home;
    if (base == null || base.isEmpty) return null;
    return p.posix
        .join(base, '.config', 'flutra', kEnvScriptName);
  }

  @override
  Future<void> killProcessTree(int pid) async {
    // Negative pid is the process *group*, which is what a shell script and
    // its java child share. SIGTERM first; the caller's timeout is the
    // backstop, not a second kill.
    try {
      await runner.run('kill', ['-TERM', '-$pid'],
          timeout: const Duration(seconds: 15));
    } catch (e) {
      _log.fine('group kill on $pid failed, falling back to pkill: $e');
      try {
        await runner.run('pkill', ['-TERM', '-P', '$pid'],
            timeout: const Duration(seconds: 15));
      } catch (_) {}
    }
  }

  @override
  Future<EnvPersistResult> persistUserEnvVar(String name, String value) async {
    final script = envScriptPath;
    if (script == null) {
      return const EnvPersistResult.failed(
          'No home directory, so there is nowhere to save it.');
    }

    try {
      final file = File(script);
      await file.parent.create(recursive: true);
      final existing = file.existsSync() ? await file.readAsString() : '';
      await file.writeAsString(upsertExport(existing, name, value));
      await _ensureSourced(script);
    } catch (e) {
      return EnvPersistResult.failed('Could not write $script: $e');
    }

    await afterPersist(name, value);
    return EnvPersistResult(
      success: true,
      restartRequired: true,
      note: persistNote,
    );
  }

  /// What to tell the user once the file is written.
  String get persistNote;

  /// A hook for the session-level trick macOS has and Linux does not.
  Future<void> afterPersist(String name, String value) async {}

  @override
  Future<EnvPersistResult> appendToUserPath(String directory) async {
    // PATH is an export like any other here; the script appends rather than
    // replaces so the user's own PATH survives.
    final script = envScriptPath;
    if (script == null) {
      return const EnvPersistResult.failed(
          'No home directory, so there is nowhere to save it.');
    }
    try {
      final file = File(script);
      await file.parent.create(recursive: true);
      final existing = file.existsSync() ? await file.readAsString() : '';
      final line = 'export PATH="\$PATH:${shellQuote(directory)}"';
      if (!existing.contains(line)) {
        final body = existing.isEmpty || existing.endsWith('\n')
            ? existing
            : '$existing\n';
        await file.writeAsString('$body$line\n');
      }
      await _ensureSourced(script);
    } catch (e) {
      return EnvPersistResult.failed('Could not write $script: $e');
    }
    return EnvPersistResult(success: true, restartRequired: true,
        note: persistNote);
  }

  /// The directories the app's own `env.sh` puts on PATH.
  ///
  /// Only this app's exports count: the rest of the user's PATH comes from
  /// files it does not own, and the process environment already covers those.
  @override
  Future<String> readUserPath() async {
    final script = envScriptPath;
    if (script == null) return '';
    final file = File(script);
    if (!file.existsSync()) return '';
    try {
      return parseExportedPathEntries(await file.readAsString()).join(':');
    } catch (e) {
      _log.fine('could not read $script: $e');
      return '';
    }
  }

  /// Makes every rc file source the script, exactly once.
  Future<void> _ensureSourced(String script) async {
    for (final rc in rcFiles) {
      final file = File(rc);
      // `.profile` is created when missing — it is the one a login shell is
      // guaranteed to read. The others are only edited when they exist, so
      // this never invents a bashrc for someone who uses zsh.
      final isPrimary = rc == rcFiles.first;
      if (!file.existsSync() && !isPrimary) continue;
      try {
        final existing = file.existsSync() ? await file.readAsString() : '';
        final updated = upsertManagedBlock(existing, script);
        if (updated != existing) await file.writeAsString(updated);
      } catch (e) {
        _log.warning('could not update $rc: $e');
      }
    }
  }

  @override
  Future<void> revealInFileManager(String path) async {
    try {
      await Process.start(revealCommand, revealArguments(path),
          mode: ProcessStartMode.detached);
    } catch (e) {
      _log.warning('could not open $path: $e');
    }
  }

  String get revealCommand;
  List<String> revealArguments(String path);
}

/// Linux: PolicyKit for elevation, `xdg-open` for the file manager.
class LinuxSystemActions extends _UnixSystemActions {
  LinuxSystemActions(super.runner, super.platform);

  @override
  List<String> get rcFiles {
    final base = home;
    if (base == null) return const [];
    return [
      p.posix.join(base, '.profile'),
      p.posix.join(base, '.bashrc'),
      p.posix.join(base, '.zshrc'),
    ];
  }

  @override
  String get persistNote =>
      'Takes effect in new terminal sessions, or after a re-login for apps '
      'launched from the desktop.';

  @override
  String get revealCommand => 'xdg-open';

  /// xdg-open has no "select this file" mode, so the folder is what opens.
  @override
  List<String> revealArguments(String path) =>
      [FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path)];

  @override
  (String, List<String>)? elevated(String command) {
    // PolicyKit shows the system's own auth dialog. Without it there is no
    // way to ask that does not involve handling a password, so the caller
    // falls back to showing the command.
    if (!File('/usr/bin/pkexec').existsSync()) return null;
    return ('pkexec', ['sh', '-c', command]);
  }
}

/// macOS: osascript for elevation, `open -R` to reveal, plus `launchctl` so
/// the current GUI session sees the variable without a re-login.
class MacosSystemActions extends _UnixSystemActions {
  MacosSystemActions(super.runner, super.platform);

  @override
  List<String> get rcFiles {
    final base = home;
    if (base == null) return const [];
    // zsh is the default shell; bash_profile is only touched if it is there.
    return [
      p.posix.join(base, '.zprofile'),
      p.posix.join(base, '.zshrc'),
      p.posix.join(base, '.bash_profile'),
    ];
  }

  @override
  String get persistNote =>
      'Saved for new terminals, and applied to this login session.';

  /// Reaches GUI-launched processes in the session that is running now.
  /// Not persistent across a reboot — the script above is what covers that.
  @override
  Future<void> afterPersist(String name, String value) async {
    try {
      await runner.run('launchctl', ['setenv', name, value],
          timeout: const Duration(seconds: 15));
    } catch (e) {
      _UnixSystemActions._log.fine('launchctl setenv failed: $e');
    }
  }

  @override
  String get revealCommand => 'open';

  @override
  List<String> revealArguments(String path) => ['-R', path];

  @override
  (String, List<String>)? elevated(String command) => (
        'osascript',
        [
          '-e',
          'do shell script "${command.replaceAll('"', r'\"')}" '
              'with administrator privileges',
        ],
      );
}

/// Builds the implementation matching the host.
@module
abstract class SystemActionsModule {
  @lazySingleton
  SystemActions actions(CommandRunner runner, PlatformService platform) {
    if (Platform.isWindows) return WindowsSystemActions(runner);
    if (Platform.isMacOS) return MacosSystemActions(runner, platform);
    return LinuxSystemActions(runner, platform);
  }
}
