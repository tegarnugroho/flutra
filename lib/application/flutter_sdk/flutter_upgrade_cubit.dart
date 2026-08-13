import 'dart:async';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/command/command_result.dart';
import '../../core/command/command_runner.dart';

part 'flutter_upgrade_state.dart';

/// Drives one `flutter upgrade`: turns the tool's raw output into the phased
/// progress the upgrade dialog draws, while keeping the lines themselves for
/// its collapsible details log.
///
/// Created per upgrade by the dialog, like `VersionSwitchCubit`, so it is not
/// registered in DI. It reads the process — it never spawns, kills or cleans up
/// anything itself; [cancel] forwards to the same [RunningCommand.cancel] the
/// generic command dialog has always called.
class FlutterUpgradeCubit extends Cubit<UpgradeProgress> {
  FlutterUpgradeCubit() : super(const UpgradeProgress());

  RunningCommand? _command;
  StreamSubscription<CommandOutputLine>? _sub;

  /// Wall clock of the phase running right now, reset at every transition, so
  /// each row can report how long its own stage took.
  final Stopwatch _phaseClock = Stopwatch();

  /// Set by [cancel] so a process the user killed is not reported as a failure.
  bool _cancelled = false;

  /// Attaches to [command] and begins mapping its output onto the phases.
  Future<void> attach(RunningCommand command) async {
    // The dialog holding this cubit can be dismissed while the command is still
    // streaming, so every emit past an await has to check.
    if (isClosed) return;
    _command = command;
    // Cancel pressed while the process was still being spawned: kill it now
    // rather than let it run on unwatched.
    if (_cancelled) command.cancel();
    _phaseClock
      ..reset()
      ..start();
    emit(state.copyWith(started: true, running: true));

    _sub = command.output.listen(_onLine);
    try {
      final result = await command.result;
      if (isClosed) return;
      _finish(result.exitCode);
    } catch (e) {
      if (isClosed) return;
      emit(state.appendLine(CommandOutputLine('$e', isError: true)));
      _finish(-1);
    } finally {
      await _sub?.cancel();
      _sub = null;
    }
  }

  /// Cancels the underlying process — the same kill the old dialog performed.
  void cancel() {
    _cancelled = true;
    _command?.cancel();
  }

  void _onLine(CommandOutputLine line) {
    if (isClosed) return;
    final next = applyUpgradeLine(state, line, _phaseClock.elapsed);
    // The clock measures one phase at a time, so it restarts the moment the
    // line moved the stepper on.
    if (next.phase != state.phase) {
      _phaseClock
        ..reset()
        ..start();
    }
    if (next != state) emit(next);
  }

  void _finish(int exitCode) {
    final success = exitCode == 0;
    final elapsed = {...state.elapsed, state.phase: _phaseClock.elapsed};
    _phaseClock.stop();
    emit(state.copyWith(
      running: false,
      finished: true,
      exitCode: exitCode,
      cancelled: _cancelled,
      elapsed: elapsed,
      completed: success ? UpgradePhase.values.toSet() : state.completed,
      phase: success ? UpgradePhase.verifying : state.phase,
      // A failure keeps the bar where it stopped; only a success fills it.
      percent: success ? 1 : state.percent,
      errorSummary:
          success || _cancelled ? null : _errorSummary(state, exitCode),
    ));
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

/// The last error line the tool printed, or the exit code when it printed none.
String _errorSummary(UpgradeProgress state, int exitCode) {
  for (final line in state.lines.reversed) {
    final text = line.text.trim();
    if (line.isError && text.isNotEmpty) {
      return text.length <= 120 ? text : '${text.substring(0, 119)}…';
    }
  }
  return 'flutter upgrade exited with code $exitCode';
}
