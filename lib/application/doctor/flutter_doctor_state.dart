part of 'flutter_doctor_cubit.dart';

enum DoctorRunStatus {
  initial,
  running,
  done,

  /// The process died, or the user cancelled it.
  interrupted,

  /// The run could not start at all.
  failure,
}

/// Where a row is in its lifecycle.
enum DoctorCheckPhase { pending, running, done }

/// One row of the doctor list, in any phase.
class DoctorCheck extends Equatable {
  const DoctorCheck({
    required this.name,
    this.phase = DoctorCheckPhase.pending,
    this.status,
    this.title,
    this.summary,
    this.details = const [],
    this.elapsed,
  });

  final String name;
  final DoctorCheckPhase phase;

  /// Set once the check resolves.
  final DoctorStatus? status;

  /// Full heading text, used by the results list.
  final String? title;

  /// Parenthetical part of the heading, shown inline while running/done.
  final String? summary;

  final List<String> details;

  /// What `flutter doctor -v` reported for this check.
  final Duration? elapsed;

  bool get isDone => phase == DoctorCheckPhase.done;
  bool get canExpand => details.isNotEmpty;

  DoctorCheck copyWith({
    DoctorCheckPhase? phase,
    DoctorStatus? status,
    String? title,
    String? summary,
    List<String>? details,
    Duration? elapsed,
  }) {
    return DoctorCheck(
      name: name,
      phase: phase ?? this.phase,
      status: status ?? this.status,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      elapsed: elapsed ?? this.elapsed,
    );
  }

  @override
  List<Object?> get props =>
      [name, phase, status, title, summary, details, elapsed];
}

/// Immutable state for the Flutter doctor screen.
class FlutterDoctorState extends Equatable {
  const FlutterDoctorState({
    this.status = DoctorRunStatus.initial,
    this.checks = const [],
    this.elapsed = Duration.zero,
    this.rawOutput,
    this.errorMessage,
    this.weights = const {},
  });

  final DoctorRunStatus status;

  /// Every row, pending ones included, so the list height is stable.
  final List<DoctorCheck> checks;

  /// Total run time: ticking while running, final when done.
  final Duration elapsed;

  /// Full `flutter doctor -v` text, for "Copy output".
  final String? rawOutput;

  final String? errorMessage;

  /// Per-check durations from the last successful run, in milliseconds, used
  /// to weight the progress bar so slow checks don't make it lie.
  final Map<String, int> weights;

  bool get isRunning => status == DoctorRunStatus.running;

  /// True once a run has produced rows. Drives the seamless hand-over: the
  /// same rows stay on screen and simply gain interactivity.
  bool get hasChecks => checks.isNotEmpty;

  int get doneCount => checks.where((c) => c.isDone).length;

  int count(DoctorStatus status) =>
      checks.where((c) => c.isDone && c.status == status).length;

  /// Fraction complete, weighted by how long each check took last time.
  /// Falls back to equal weights on the first ever run.
  double get progress {
    if (checks.isEmpty) return 0;
    double weightOf(DoctorCheck c) => (weights[c.name] ?? 0).toDouble();
    final total = checks.fold<double>(0, (sum, c) => sum + weightOf(c));
    if (total <= 0) return doneCount / checks.length;
    final done = checks
        .where((c) => c.isDone)
        .fold<double>(0, (sum, c) => sum + weightOf(c));
    return (done / total).clamp(0.0, 1.0);
  }

  /// The report the results view and "Copy output" use.
  DoctorReport? get report {
    if (!hasChecks) return null;
    return DoctorReport(
      sections: [
        for (final c in checks)
          if (c.isDone)
            DoctorSection(
              status: c.status ?? DoctorStatus.info,
              title: c.title ?? c.name,
              details: c.details,
              elapsed: c.elapsed,
            ),
      ],
      rawOutput: rawOutput ?? '',
    );
  }

  FlutterDoctorState copyWith({
    DoctorRunStatus? status,
    List<DoctorCheck>? checks,
    Duration? elapsed,
    String? rawOutput,
    String? errorMessage,
    bool clearError = false,
    Map<String, int>? weights,
  }) {
    return FlutterDoctorState(
      status: status ?? this.status,
      checks: checks ?? this.checks,
      elapsed: elapsed ?? this.elapsed,
      rawOutput: rawOutput ?? this.rawOutput,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      weights: weights ?? this.weights,
    );
  }

  @override
  List<Object?> get props =>
      [status, checks, elapsed, rawOutput, errorMessage, weights];
}
