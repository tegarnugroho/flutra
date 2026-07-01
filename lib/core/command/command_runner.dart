import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../error/failures.dart';
import 'command_result.dart';

/// Handle to a process that is currently running.
///
/// Exposes a broadcast [output] stream of lines as they are produced, a
/// [result] future that completes when the process exits, and [cancel] to
/// terminate it early.
class RunningCommand {
  RunningCommand._(this._process, this.output, this.result);

  final Process _process;

  /// Live, line-by-line output from stdout and stderr.
  final Stream<CommandOutputLine> output;

  /// Completes when the process terminates with a fully-buffered result.
  final Future<CommandResult> result;

  int get pid => _process.pid;

  /// Sends a kill signal to the process. Safe to call multiple times.
  void cancel() => _process.kill(ProcessSignal.sigterm);

  /// Writes a line to the process' stdin (used for interactive tools such as
  /// `sdkmanager --licenses`, which prompt for y/N answers).
  void writeLine(String line) => _process.stdin.writeln(line);
}

/// Central service for executing external command-line tools.
///
/// All process interaction in the app goes through this class so that timeouts,
/// cancellation, logging and error classification are handled consistently.
@lazySingleton
class CommandRunner {
  CommandRunner();

  static final Logger _log = Logger('CommandRunner');

  /// Runs [executable] with [arguments] and buffers all output.
  ///
  /// Throws [ExecutableNotFoundFailure] if the binary cannot be spawned and a
  /// [TimeoutFailure] if [timeout] elapses before the process exits. A non-zero
  /// exit code does NOT throw — inspect [CommandResult.isSuccess] instead, since
  /// several Android tools use exit codes as meaningful signals.
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    bool runInShell = true,
  }) async {
    final command = await start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );

    if (timeout == null) return command.result;

    try {
      return await command.result.timeout(timeout);
    } on TimeoutException {
      command.cancel();
      throw TimeoutFailure(
        '"$executable" did not finish within ${timeout.inSeconds}s.',
        suggestion: 'The tool may be waiting for input or is unresponsive.',
      );
    }
  }

  /// Spawns a process and returns a [RunningCommand] for live streaming and
  /// cancellation. Throws [ExecutableNotFoundFailure] if the process cannot be
  /// started.
  Future<RunningCommand> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = true,
  }) async {
    _log.fine('exec: $executable ${arguments.join(' ')}');

    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: runInShell,
      );
    } on ProcessException catch (e) {
      _log.warning('failed to start "$executable": ${e.message}');
      throw ExecutableNotFoundFailure(
        executable,
        suggestion: 'Verify the tool is installed and its path is configured '
            'in Environment Settings.',
      );
    }

    final stopwatch = Stopwatch()..start();
    final outputController = StreamController<CommandOutputLine>.broadcast();
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    Stream<void> pipe(Stream<List<int>> src, StringBuffer buf, bool isErr) {
      return src
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        buf.writeln(line);
        if (!outputController.isClosed) {
          outputController.add(CommandOutputLine(line, isError: isErr));
        }
      });
    }

    final drained = Future.wait([
      pipe(process.stdout, stdoutBuffer, false).drain<void>(),
      pipe(process.stderr, stderrBuffer, true).drain<void>(),
    ]);

    final result = () async {
      final code = await process.exitCode;
      await drained; // ensure all lines flushed before completing
      stopwatch.stop();
      await outputController.close();
      return CommandResult(
        executable: executable,
        arguments: arguments,
        exitCode: code,
        stdout: stdoutBuffer.toString().trimRight(),
        stderr: stderrBuffer.toString().trimRight(),
        duration: stopwatch.elapsed,
      );
    }();

    return RunningCommand._(process, outputController.stream, result);
  }

  /// Resolves the absolute path of [executable] using the system PATH.
  ///
  /// Returns null when the binary is not found. Uses `where` on Windows.
  Future<String?> which(String executable) async {
    try {
      final result = await run(
        Platform.isWindows ? 'where' : 'which',
        [executable],
        timeout: const Duration(seconds: 5),
      );
      if (!result.isSuccess) return null;
      final first = const LineSplitter()
          .convert(result.stdout)
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      return first.isEmpty ? null : first;
    } on Failure {
      return null;
    }
  }
}
