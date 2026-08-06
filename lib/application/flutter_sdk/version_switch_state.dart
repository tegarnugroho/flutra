part of 'version_switch_cubit.dart';

/// Observable progress of one version switch.
class VersionSwitchProgress extends Equatable {
  const VersionSwitchProgress({
    required this.version,
    this.step,
    this.completed = const {},
    this.lines = const [],
    this.started = false,
    this.running = false,
    this.finished = false,
    this.outcome,
    this.failure,
  });

  /// The release being switched to, used to label the checkout step.
  final String version;

  /// The stage running right now, null before the first one starts.
  final VersionSwitchStep? step;

  /// Stages that already succeeded.
  final Set<VersionSwitchStep> completed;

  /// git/flutter output collected so far.
  final List<CommandOutputLine> lines;

  final bool started;
  final bool running;
  final bool finished;

  /// Set once the switch succeeded.
  final VersionSwitchOutcome? outcome;

  /// Set once the switch failed; carries the rollback verdict.
  final VersionSwitchFailed? failure;

  bool get isSuccess => finished && outcome != null;

  VersionSwitchProgress copyWith({
    VersionSwitchStep? step,
    Set<VersionSwitchStep>? completed,
    List<CommandOutputLine>? lines,
    bool? started,
    bool? running,
    bool? finished,
    VersionSwitchOutcome? outcome,
    VersionSwitchFailed? failure,
  }) {
    return VersionSwitchProgress(
      version: version,
      step: step ?? this.step,
      completed: completed ?? this.completed,
      lines: lines ?? this.lines,
      started: started ?? this.started,
      running: running ?? this.running,
      finished: finished ?? this.finished,
      outcome: outcome ?? this.outcome,
      failure: failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => [
        version,
        step,
        completed,
        lines,
        started,
        running,
        finished,
        outcome,
        failure?.message,
      ];
}
