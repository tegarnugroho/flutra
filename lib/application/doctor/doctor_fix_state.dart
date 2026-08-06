part of 'doctor_fix_cubit.dart';

/// Where a fix is in its lifecycle.
enum FixPhase { idle, running, finished }

/// Observable state of the one fix that may be in flight.
class DoctorFixState extends Equatable {
  const DoctorFixState({
    this.phase = FixPhase.idle,
    this.issueId,
    this.issueTitle,
    this.lines = const [],
    this.outcome,
  });

  final FixPhase phase;

  /// Which issue this is about; null while idle.
  final String? issueId;
  final String? issueTitle;

  /// Tool output collected so far.
  final List<CommandOutputLine> lines;

  /// Set once the fix ends, successfully or not.
  final FixOutcome? outcome;

  bool get isRunning => phase == FixPhase.running;
  bool get isFinished => phase == FixPhase.finished;
  bool get succeeded => isFinished && (outcome?.success ?? false);

  /// True when the change needs new processes to be visible, so re-running
  /// doctor straight away would still report the old state.
  bool get needsRestart => outcome?.restartRequired ?? false;

  /// True while something outside the app (the Visual Studio installer) is
  /// still working.
  bool get blocksRerun => outcome?.blocksRerun ?? false;

  /// Whether the page should re-run doctor by itself once this is done.
  bool get shouldRerun => succeeded && !needsRestart && !blocksRerun;

  DoctorFixState copyWith({
    FixPhase? phase,
    String? issueId,
    String? issueTitle,
    List<CommandOutputLine>? lines,
    FixOutcome? outcome,
  }) {
    return DoctorFixState(
      phase: phase ?? this.phase,
      issueId: issueId ?? this.issueId,
      issueTitle: issueTitle ?? this.issueTitle,
      lines: lines ?? this.lines,
      outcome: outcome ?? this.outcome,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        issueId,
        issueTitle,
        lines,
        outcome?.success,
        outcome?.note,
        outcome?.restartRequired,
        outcome?.blocksRerun,
      ];
}
