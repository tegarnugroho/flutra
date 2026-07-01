import 'package:equatable/equatable.dart';

/// Immutable result of a finished process execution.
class CommandResult extends Equatable {
  const CommandResult({
    required this.executable,
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });

  final String executable;
  final List<String> arguments;
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  /// A process is considered successful when it terminates with exit code 0.
  bool get isSuccess => exitCode == 0;

  /// Combined output, useful for tools that mix streams (e.g. `flutter doctor`).
  String get combinedOutput {
    if (stderr.isEmpty) return stdout;
    if (stdout.isEmpty) return stderr;
    return '$stdout\n$stderr';
  }

  String get commandLine => '$executable ${arguments.join(' ')}';

  @override
  List<Object?> get props => [executable, arguments, exitCode, stdout, stderr];
}

/// A single line emitted while a process is running, tagged by its source stream.
class CommandOutputLine extends Equatable {
  const CommandOutputLine(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  List<Object?> get props => [text, isError];
}
