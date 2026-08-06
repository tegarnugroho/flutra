import 'dart:async';

import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';
import '../../core/platform/platform_service.dart';
import '../../domain/entities/doctor_report.dart';

/// The default check order used before a successful run has been recorded.
///
/// Matches what `flutter doctor -v` prints on Windows.
const kDefaultDoctorChecks = <String>[
  'Flutter',
  'Windows Version',
  'Android toolchain',
  'Chrome',
  'Visual Studio',
  'Android Studio',
  'Connected device',
  'Network resources',
];

/// Events emitted while `flutter doctor -v` runs.
sealed class DoctorEvent {
  const DoctorEvent();
}

/// The process started; [expected] is the check list the UI can pre-render.
class DoctorRunStarted extends DoctorEvent {
  const DoctorRunStarted(this.expected);

  final List<String> expected;
}

/// The named check is now the one being waited on.
class DoctorCheckStarted extends DoctorEvent {
  const DoctorCheckStarted(this.name);

  final String name;
}

/// A check finished: its marker line arrived.
///
/// Details are NOT included here — `flutter doctor` prints them *after* the
/// marker, so waiting for them would hold every row back by one check. They
/// follow in [DoctorCheckDetails], before the row can be expanded anyway.
class DoctorCheckResolved extends DoctorEvent {
  const DoctorCheckResolved({
    required this.name,
    required this.status,
    required this.title,
    required this.summary,
    this.elapsed,
  });

  final String name;
  final DoctorStatus status;

  /// The full heading text, e.g. "Flutter (Channel stable, 3.44.8, on …)".
  final String title;

  /// The parenthetical part of the heading, or null when there is none.
  final String? summary;

  /// What `flutter doctor -v` itself reported for this check.
  final Duration? elapsed;
}

/// The indented lines that belong to a resolved check.
class DoctorCheckDetails extends DoctorEvent {
  const DoctorCheckDetails(this.name, this.lines);

  final String name;
  final List<String> lines;
}

/// The process exited normally.
class DoctorRunCompleted extends DoctorEvent {
  const DoctorRunCompleted({
    required this.passed,
    required this.total,
    required this.totalElapsed,
    required this.rawOutput,
  });

  final int passed;
  final int total;
  final Duration totalElapsed;
  final String rawOutput;
}

/// The process could not start, died, or was cancelled.
class DoctorRunFailed extends DoctorEvent {
  const DoctorRunFailed(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;
}

/// Runs `flutter doctor -v` and reports progress as it streams.
///
/// `flutter doctor --machine` is not an option: this Flutter rejects it with
/// "The --machine flag is only valid with the --version flag", so the `-v`
/// text output is the only source.
@lazySingleton
class DoctorRunner {
  DoctorRunner(this._runner, this._platform);

  final CommandRunner _runner;
  final PlatformService _platform;

  RunningCommand? _current;

  bool get isRunning => _current != null;

  /// Starts a run and streams its events.
  ///
  /// [expectedChecks] pre-populates the UI; unknown names that stream in are
  /// appended rather than dropped.
  Stream<DoctorEvent> run({
    List<String> expectedChecks = kDefaultDoctorChecks,
  }) {
    final controller = StreamController<DoctorEvent>();
    unawaited(_run(controller, expectedChecks));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<DoctorEvent> controller,
    List<String> expectedChecks,
  ) async {
    final stopwatch = Stopwatch()..start();
    final parser = DoctorStreamParser();
    final raw = StringBuffer();
    var index = 0;

    void startNext() {
      if (index < expectedChecks.length) {
        controller.add(DoctorCheckStarted(expectedChecks[index]));
        index++;
      }
    }

    try {
      final command = await _runner.start(
        _platform.flutterExecutable,
        ['doctor', '-v'],
      );
      _current = command;
      controller.add(DoctorRunStarted(expectedChecks));
      startNext();

      final sub = command.output.listen((line) {
        raw.writeln(line.text);
        for (final event in parser.feed(line.text)) {
          controller.add(event);
          if (event is DoctorCheckResolved) startNext();
        }
      });

      final result = await command.result;
      await sub.cancel();
      for (final event in parser.flush()) {
        controller.add(event);
      }
      stopwatch.stop();
      _current = null;

      final cancelled = _cancelled;
      _cancelled = false;
      if (cancelled) {
        controller.add(const DoctorRunFailed('Cancelled', cancelled: true));
      } else if (parser.resolved.isEmpty) {
        controller.add(DoctorRunFailed(
          result.combinedOutput.trim().isEmpty
              ? 'flutter doctor produced no output.'
              : result.combinedOutput.trim(),
        ));
      } else {
        controller.add(DoctorRunCompleted(
          passed: parser.resolved
              .where((r) => r.status == DoctorStatus.ok)
              .length,
          total: parser.resolved.length,
          totalElapsed: stopwatch.elapsed,
          rawOutput: raw.toString(),
        ));
      }
    } catch (e) {
      _current = null;
      controller.add(DoctorRunFailed('$e'));
    } finally {
      await controller.close();
    }
  }

  bool _cancelled = false;

  /// Kills the running process; the stream ends with a cancelled failure.
  void cancel() {
    final command = _current;
    if (command == null) return;
    _cancelled = true;
    command.cancel();
  }
}

/// Incremental parser for `flutter doctor -v` output.
///
/// Kept separate and pure so it can be unit-tested against captured fixtures.
class DoctorStreamParser {
  /// A heading looks like `[√] Flutter (Channel stable, …) [353ms]`.
  ///
  /// The marker really is `√` (U+221A) on the Windows console — not `✓`
  /// (U+2713) — so both are accepted, along with the ASCII fallbacks.
  static final RegExp _header = RegExp(r'^\[(.)\]\s?(.*)$');

  /// Trailing duration `flutter doctor -v` prints per check: `[353ms]`,
  /// `[3.4s]`, `[1,821ms]`.
  static final RegExp _elapsed = RegExp(r'\s*\[([\d.,]+)\s*(ms|s)\]\s*$');

  static final RegExp _parenthetical = RegExp(r'\(([^)]*)\)');

  final List<DoctorCheckResolved> resolved = [];

  String? _openCheck;
  List<String> _details = [];

  /// Feeds one output line, returning any events it produced.
  List<DoctorEvent> feed(String rawLine) {
    final line = rawLine.trimRight();
    final match = _header.firstMatch(line.trimLeft());
    // Indented `[…]` lines belong to the previous check's details.
    final isHeader = match != null && !rawLine.startsWith(' ');
    if (!isHeader) {
      if (_openCheck != null) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) _details.add(trimmed);
      }
      return const [];
    }

    final events = <DoctorEvent>[];
    events.addAll(_closeOpenCheck());

    final status = statusFromMarker(match.group(1)!);
    final titleWithTime = (match.group(2) ?? '').trim();
    final elapsed = parseElapsed(titleWithTime);
    final title = titleWithTime.replaceAll(_elapsed, '').trim();
    final name = checkName(title);

    final event = DoctorCheckResolved(
      name: name,
      status: status,
      title: title,
      summary: _parenthetical.firstMatch(title)?.group(1)?.trim(),
      elapsed: elapsed,
    );
    resolved.add(event);
    events.add(event);

    _openCheck = name;
    _details = [];
    return events;
  }

  /// Closes the last check at end of output.
  List<DoctorEvent> flush() => _closeOpenCheck();

  List<DoctorEvent> _closeOpenCheck() {
    final open = _openCheck;
    if (open == null) return const [];
    final details = _details;
    _openCheck = null;
    _details = [];
    return details.isEmpty
        ? const []
        : [DoctorCheckDetails(open, List.unmodifiable(details))];
  }

  /// The short name used to match a check against the expected list, e.g.
  /// "Android toolchain" from "Android toolchain - develop for Android …".
  static String checkName(String title) {
    var name = title;
    final paren = name.indexOf('(');
    if (paren > 0) name = name.substring(0, paren);
    final dash = name.indexOf(' - ');
    if (dash > 0) name = name.substring(0, dash);
    return name.trim();
  }

  /// Maps a marker glyph to a status, tolerating console codepage variants.
  static DoctorStatus statusFromMarker(String marker) => switch (marker) {
        // U+221A on the Windows console, U+2713 elsewhere.
        '√' || '✓' || '+' => DoctorStatus.ok,
        '!' => DoctorStatus.warning,
        '✗' || '✘' || 'x' || 'X' => DoctorStatus.error,
        _ => DoctorStatus.info,
      };

  /// Reads the `[353ms]` / `[3.4s]` / `[1,821ms]` suffix flutter prints.
  static Duration? parseElapsed(String title) {
    final match = _elapsed.firstMatch(title);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (value == null) return null;
    return match.group(2) == 's'
        ? Duration(microseconds: (value * 1000000).round())
        : Duration(microseconds: (value * 1000).round());
  }
}
