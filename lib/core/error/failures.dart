import 'package:equatable/equatable.dart';

/// Base type for all recoverable, user-facing errors in the app.
///
/// Every failure carries a human [message] and an optional [suggestion] the UI
/// can surface as a recovery hint.
abstract class Failure extends Equatable {
  const Failure(this.message, {this.suggestion, this.cause});

  final String message;
  final String? suggestion;
  final Object? cause;

  @override
  List<Object?> get props => [message, suggestion];

  @override
  String toString() => '$runtimeType($message)';
}

/// A required command-line executable could not be located on the system.
class ExecutableNotFoundFailure extends Failure {
  const ExecutableNotFoundFailure(
    this.executable, {
    super.suggestion,
  }) : super('Could not find "$executable" on this system.');

  final String executable;

  @override
  List<Object?> get props => [...super.props, executable];
}

/// A process ran but terminated with a non-zero exit code.
class ProcessFailure extends Failure {
  const ProcessFailure(
    super.message, {
    required this.exitCode,
    this.output,
    super.suggestion,
    super.cause,
  });

  final int exitCode;
  final String? output;

  @override
  List<Object?> get props => [...super.props, exitCode];
}

/// A process exceeded its allotted runtime and was killed.
class TimeoutFailure extends Failure {
  const TimeoutFailure(super.message, {super.suggestion});
}

/// The operation was cancelled by the user.
class CancelledFailure extends Failure {
  const CancelledFailure() : super('Operation was cancelled.');
}

/// A network / download error (missing connectivity, proxy, corrupt archive).
class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.suggestion, super.cause});
}

/// Filesystem / permission problems (SDK path not writable, etc.).
class FileSystemFailure extends Failure {
  const FileSystemFailure(super.message, {super.suggestion, super.cause});
}

/// A generic, unexpected error we could not classify.
class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.cause});
}
