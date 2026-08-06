import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/command/command_result.dart';
import '../../domain/entities/version_switch.dart';

part 'version_switch_state.dart';

/// Drives one version switch: subscribes to the repository's event stream and
/// turns it into the progress list and log the dialog renders.
///
/// Created per switch by the dialog, like [CommandLogCubit], so it is not
/// registered in DI.
class VersionSwitchCubit extends Cubit<VersionSwitchProgress> {
  VersionSwitchCubit(String version, this._start)
      : super(VersionSwitchProgress(version: version));

  final Stream<VersionSwitchEvent> Function() _start;

  StreamSubscription<VersionSwitchEvent>? _sub;

  /// Starts the switch. The stream reports failures as events, so the only way
  /// this ends unexpectedly is an error out of the stream itself.
  Future<void> run() async {
    if (isClosed || state.started) return;
    emit(state.copyWith(started: true, running: true));
    final done = Completer<void>();
    _sub = _start().listen(
      _apply,
      onError: (Object e) => _apply(VersionSwitchFailed('$e')),
      onDone: () {
        // A stream that ends without a verdict means the switch was torn down
        // mid-flight; treat it as a failure rather than a silent success.
        if (!isClosed && state.running) {
          _apply(const VersionSwitchFailed('The switch stopped unexpectedly.'));
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: false,
    );
    await done.future;
  }

  void _apply(VersionSwitchEvent event) {
    if (isClosed) return;
    switch (event) {
      case VersionSwitchStepStarted(:final step):
        emit(state.copyWith(
          step: step,
          completed: {...state.completed, if (state.step != null) state.step!},
        ));
      case VersionSwitchLogged(:final text, :final isError):
        if (text.trim().isEmpty) return;
        emit(state.copyWith(
          lines: [...state.lines, CommandOutputLine(text, isError: isError)],
        ));
      case VersionSwitchSucceeded(:final outcome):
        emit(state.copyWith(
          running: false,
          finished: true,
          completed: VersionSwitchStep.values.toSet(),
          step: VersionSwitchStep.done,
          outcome: outcome,
        ));
      case VersionSwitchFailed():
        emit(state.copyWith(
          running: false,
          finished: true,
          failure: event,
          lines: [...state.lines, CommandOutputLine(event.message, isError: true)],
        ));
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
