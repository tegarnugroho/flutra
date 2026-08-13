part of 'flutter_upgrade_cubit.dart';

/// The stages one `flutter upgrade` moves through, in the order the tool runs
/// them, each weighted by the share of the whole it usually takes.
///
/// The weights only drive the bar. They are a rough share of the work, never an
/// estimate of time remaining — the dialog does not show one.
enum UpgradePhase {
  downloading('Downloading archive', 40),
  extracting('Extracting files', 15),
  buildingTool('Building Flutter tool', 20),
  upgradingEngine('Upgrading engine', 20),
  verifying('Verifying installation', 5);

  const UpgradePhase(this.label, this.weight);

  final String label;
  final int weight;
}

/// How one phase row draws itself.
enum UpgradePhaseStatus { pending, active, done, failed }

/// Line patterns that mark the start of a phase, tested in order — the first
/// match wins, so the stage-specific patterns sit above the generic ones.
///
/// `flutter upgrade` reports nothing structured, only stdout, so the phases are
/// read off its prose. Two traps are deliberately handled here:
///
///  * `Upgrading engine...` is printed *before* the Dart SDK download, as a
///    header for that whole step, so it is not an [UpgradePhase.upgradingEngine]
///    marker. That phase is recognised by the artifact lines instead.
///  * `Downloading Windows x64 Dart SDK from Flutter engine …` belongs to the
///    download phase even though the artifact lines also start with
///    "Downloading", which is why it is tested first.
///
// TODO(tegar): re-check these against a real upgrade on each channel — the tool
// rewords its output between releases, and a phase that never matches simply
// stays folded into the previous one rather than breaking the dialog.
final _phasePatterns = <(RegExp, UpgradePhase)>[
  (RegExp(r'^Unzipping\b'), UpgradePhase.extracting),
  (RegExp(r'^Expanding downloaded archive'), UpgradePhase.extracting),
  (RegExp(r'^Building flutter tool'), UpgradePhase.buildingTool),
  (RegExp(r'^Running pub upgrade'), UpgradePhase.buildingTool),
  (RegExp(r'^Resolving dependencies'), UpgradePhase.buildingTool),
  (RegExp(r'^Got dependencies'), UpgradePhase.buildingTool),
  (RegExp(r'Dart SDK from Flutter engine'), UpgradePhase.downloading),
  (RegExp(r'^\[\s*\d+/\d+\]'), UpgradePhase.upgradingEngine),
  (
    RegExp(
      r'^Downloading .*(fonts|Gradle Wrapper|sky_engine|tools|artifacts|'
      r'maven|engine)',
    ),
    UpgradePhase.upgradingEngine,
  ),
  (RegExp(r'^Upgrading Flutter to '), UpgradePhase.downloading),
  (
    RegExp(r'^(From |remote:|Receiving objects|Resolving deltas|Updating files|'
        r'Checking out files)'),
    UpgradePhase.downloading,
  ),
  (RegExp(r'^Flutter\s+\d+\.\d+\.\d+'), UpgradePhase.verifying),
  (RegExp(r'^Framework\s+•\s+revision'), UpgradePhase.verifying),
];

/// The phase [line] announces, or null when it says nothing about progress.
UpgradePhase? upgradePhaseFor(String line) {
  final text = line.trim();
  if (text.isEmpty) return null;
  for (final (pattern, phase) in _phasePatterns) {
    if (pattern.hasMatch(text)) return phase;
  }
  return null;
}

/// Progress *within* [phase], 0..1, for the two stages the tool counts out
/// loud: git's `Receiving objects:  42%` and the `[3/11]` artifact tally.
///
/// Null when the line carries no such signal — the bar then snaps to the phase
/// boundary and the width tween smooths the jump.
double? intraPhaseFraction(String line, UpgradePhase phase) {
  final text = line.trim();
  if (phase == UpgradePhase.downloading) {
    final match = RegExp(r'Receiving objects:\s+(\d+)%').firstMatch(text);
    if (match != null) return int.parse(match.group(1)!) / 100;
  }
  final tally = RegExp(r'^\[\s*(\d+)/(\d+)\]').firstMatch(text);
  if (tally != null) {
    final total = int.parse(tally.group(2)!);
    if (total > 0) return int.parse(tally.group(1)!) / total;
  }
  return null;
}

/// Share of the whole upgrade completed when [phase] is [fraction] through it.
double upgradePercentAt(UpgradePhase phase, double fraction) {
  var before = 0;
  for (final p in UpgradePhase.values) {
    if (p.index < phase.index) before += p.weight;
  }
  final total = UpgradePhase.values.fold<int>(0, (sum, p) => sum + p.weight);
  final within = phase.weight * fraction.clamp(0.0, 1.0);
  return ((before + within) / total).clamp(0.0, 1.0);
}

/// Folds one output [line] into [state]: appends it to the log, moves the
/// stepper on if it announces a new phase, and recomputes the bar.
///
/// [phaseElapsed] is the wall clock of the phase running now, recorded against
/// that phase if this line ends it. Pure, so the whole mapping is testable
/// without a process behind it.
UpgradeProgress applyUpgradeLine(
  UpgradeProgress state,
  CommandOutputLine line,
  Duration phaseElapsed,
) {
  var next = state.appendLine(line);

  final matched = upgradePhaseFor(line.text);
  // Phases only ever move forward: `flutter upgrade` prints some headers ahead
  // of the work they describe, so a late match must not walk the stepper back.
  if (matched != null && matched.index > next.phase.index) {
    next = next.advanceTo(matched, phaseElapsed);
  }

  final within = intraPhaseFraction(line.text, next.phase);
  final fraction = math.max(next.phaseFraction, within ?? 0);
  return next.copyWith(
    phaseFraction: fraction,
    // Monotonic: a phase that reports no progress of its own must not drag the
    // bar back to its own boundary.
    percent: math.max(next.percent, upgradePercentAt(next.phase, fraction)),
  );
}

/// A finished phase's wall clock, as `8s` or `1m 05s`.
String formatPhaseDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}m ${rest}s';
}

/// Observable progress of one upgrade.
class UpgradeProgress extends Equatable {
  const UpgradeProgress({
    this.phase = UpgradePhase.downloading,
    this.completed = const {},
    this.elapsed = const {},
    this.phaseFraction = 0,
    this.percent = 0,
    this.lines = const [],
    this.totalLines = 0,
    this.started = false,
    this.running = false,
    this.finished = false,
    this.cancelled = false,
    this.exitCode,
    this.errorSummary,
  });

  /// How many log lines the buffer keeps. The dialog only shows the last few;
  /// the rest are held so a failure can be read back without re-running.
  static const logLimit = 200;

  /// The phase running now — or the one it stopped in, once finished.
  final UpgradePhase phase;

  /// Phases that already finished.
  final Set<UpgradePhase> completed;

  /// Wall clock per phase, recorded as each one ends. A phase the output
  /// skipped past has no entry and its row shows no time.
  final Map<UpgradePhase, Duration> elapsed;

  /// Progress inside [phase], 0..1, where the tool reports it.
  final double phaseFraction;

  /// Overall progress, 0..1. Monotonic — it never walks backwards.
  final double percent;

  /// The tail of the raw output, capped at [logLimit].
  final List<CommandOutputLine> lines;

  /// Lines seen in total, including the ones the buffer dropped. Gives every
  /// visible line a stable identity so it fades in exactly once.
  final int totalLines;

  final bool started;
  final bool running;
  final bool finished;

  /// True when the user pressed Cancel — a killed process is not a failure.
  final bool cancelled;

  final int? exitCode;

  /// One line describing why the upgrade failed, for the phase label.
  final String? errorSummary;

  bool get isSuccess => finished && exitCode == 0;
  bool get isFailure => finished && exitCode != 0 && !cancelled;

  /// How the [phase] row draws itself right now.
  UpgradePhaseStatus statusOf(UpgradePhase phase) {
    if (completed.contains(phase)) return UpgradePhaseStatus.done;
    if (phase != this.phase) return UpgradePhaseStatus.pending;
    if (isFailure) return UpgradePhaseStatus.failed;
    if (running) return UpgradePhaseStatus.active;
    // Not started yet, or stopped by Cancel: nothing is spinning.
    return UpgradePhaseStatus.pending;
  }

  /// This state with [line] appended, dropping the oldest line once [logLimit]
  /// is reached so a long upgrade cannot grow the state without bound. Blank
  /// lines are ignored — the tool prints plenty and none of them read as
  /// progress.
  UpgradeProgress appendLine(CommandOutputLine line) {
    if (line.text.trim().isEmpty) return this;
    final next = [...lines, line];
    return copyWith(
      lines: next.length > logLimit
          ? next.sublist(next.length - logLimit)
          : next,
      totalLines: totalLines + 1,
    );
  }

  /// This state with the stepper moved on to [to], closing off every phase
  /// before it and recording [phaseElapsed] against the phase being left.
  ///
  /// A phase the output skipped over is marked done with no duration rather
  /// than a made-up one — its row simply shows no time.
  UpgradeProgress advanceTo(UpgradePhase to, Duration phaseElapsed) {
    return copyWith(
      phase: to,
      completed: {
        ...completed,
        for (final p in UpgradePhase.values)
          if (p.index < to.index) p,
      },
      elapsed: {...elapsed, phase: phaseElapsed},
      phaseFraction: 0,
    );
  }

  /// The last [count] log lines, newest last.
  List<CommandOutputLine> tail(int count) =>
      lines.length <= count ? lines : lines.sublist(lines.length - count);

  /// Absolute index of the [i]-th line of `tail(count)`, stable as the buffer
  /// scrolls, so an already-visible line is not re-animated.
  int tailIndex(int count, int i) =>
      totalLines - math.min<int>(count, lines.length) + i;

  UpgradeProgress copyWith({
    UpgradePhase? phase,
    Set<UpgradePhase>? completed,
    Map<UpgradePhase, Duration>? elapsed,
    double? phaseFraction,
    double? percent,
    List<CommandOutputLine>? lines,
    int? totalLines,
    bool? started,
    bool? running,
    bool? finished,
    bool? cancelled,
    int? exitCode,
    String? errorSummary,
  }) {
    return UpgradeProgress(
      phase: phase ?? this.phase,
      completed: completed ?? this.completed,
      elapsed: elapsed ?? this.elapsed,
      phaseFraction: phaseFraction ?? this.phaseFraction,
      percent: percent ?? this.percent,
      lines: lines ?? this.lines,
      totalLines: totalLines ?? this.totalLines,
      started: started ?? this.started,
      running: running ?? this.running,
      finished: finished ?? this.finished,
      cancelled: cancelled ?? this.cancelled,
      exitCode: exitCode ?? this.exitCode,
      errorSummary: errorSummary ?? this.errorSummary,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        completed,
        elapsed,
        phaseFraction,
        percent,
        lines,
        totalLines,
        started,
        running,
        finished,
        cancelled,
        exitCode,
        errorSummary,
      ];
}
