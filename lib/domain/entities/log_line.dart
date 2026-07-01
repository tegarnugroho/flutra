import 'package:equatable/equatable.dart';

/// Android logcat priority levels, ordered by severity.
enum LogPriority { verbose, debug, info, warn, error, fatal, unknown }

extension LogPriorityInfo on LogPriority {
  /// Numeric rank for "minimum priority" filtering (verbose lowest).
  int get rank => switch (this) {
        LogPriority.verbose => 0,
        LogPriority.debug => 1,
        LogPriority.info => 2,
        LogPriority.warn => 3,
        LogPriority.error => 4,
        LogPriority.fatal => 5,
        LogPriority.unknown => 0,
      };

  String get label => switch (this) {
        LogPriority.verbose => 'Verbose',
        LogPriority.debug => 'Debug',
        LogPriority.info => 'Info',
        LogPriority.warn => 'Warn',
        LogPriority.error => 'Error',
        LogPriority.fatal => 'Fatal',
        LogPriority.unknown => 'Unknown',
      };

  String get letter => switch (this) {
        LogPriority.verbose => 'V',
        LogPriority.debug => 'D',
        LogPriority.info => 'I',
        LogPriority.warn => 'W',
        LogPriority.error => 'E',
        LogPriority.fatal => 'F',
        LogPriority.unknown => '?',
      };

  static LogPriority fromLetter(String c) => switch (c.toUpperCase()) {
        'V' => LogPriority.verbose,
        'D' => LogPriority.debug,
        'I' => LogPriority.info,
        'W' => LogPriority.warn,
        'E' => LogPriority.error,
        'F' => LogPriority.fatal,
        _ => LogPriority.unknown,
      };
}

/// One line of streamed output, optionally parsed into logcat fields.
class LogLine extends Equatable {
  const LogLine({
    required this.raw,
    this.priority = LogPriority.unknown,
    this.tag,
    this.message,
    this.isError = false,
  });

  final String raw;
  final LogPriority priority;
  final String? tag;

  /// Message body (after priority/tag) for logcat lines; null otherwise.
  final String? message;

  /// True when the line came from stderr (non-logcat streams).
  final bool isError;

  /// Parses a logcat line in the `brief` format: `I/Tag( 1234): message`.
  /// Falls back to an unknown-priority line when it doesn't match.
  factory LogLine.parseLogcat(String raw) {
    final match =
        RegExp(r'^([VDIWEF])/(.+?)\(\s*\d+\):\s?(.*)$').firstMatch(raw);
    if (match != null) {
      return LogLine(
        raw: raw,
        priority: LogPriorityInfo.fromLetter(match.group(1)!),
        tag: match.group(2)!.trim(),
        message: match.group(3),
      );
    }
    return LogLine(raw: raw);
  }

  /// A plain (non-logcat) line, e.g. emulator stdout/stderr.
  factory LogLine.plain(String raw, {bool isError = false}) =>
      LogLine(raw: raw, isError: isError);

  @override
  List<Object?> get props => [raw, priority, tag, isError];
}
