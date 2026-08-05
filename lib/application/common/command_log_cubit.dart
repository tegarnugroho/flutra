import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/command/command_result.dart';
import '../../core/command/command_runner.dart';

/// Streams a running command's output into an observable log, tracking
/// completion and exit status. Created per-operation (install, licenses, …),
/// not registered in DI.
class CommandLogCubit extends Cubit<CommandLogState> {
  CommandLogCubit() : super(const CommandLogState());

  RunningCommand? _command;
  StreamSubscription<CommandOutputLine>? _sub;

  /// Attaches to [command] and begins collecting its output.
  Future<void> attach(RunningCommand command) async {
    // The dialog holding this cubit can be dismissed while the command is
    // still streaming, so every emit past an await has to check.
    if (isClosed) return;
    _command = command;
    emit(const CommandLogState(running: true));

    _sub = command.output.listen((line) {
      if (isClosed) return;
      emit(state.copyWith(lines: [...state.lines, line]));
    });

    try {
      final result = await command.result;
      if (isClosed) return;
      emit(state.copyWith(
        running: false,
        exitCode: result.exitCode,
        finished: true,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        running: false,
        finished: true,
        exitCode: -1,
        lines: [...state.lines, CommandOutputLine('$e', isError: true)],
      ));
    } finally {
      await _sub?.cancel();
      _sub = null;
    }
  }

  /// Cancels the underlying process.
  void cancel() => _command?.cancel();

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

/// Observable state of a streaming command.
class CommandLogState extends Equatable {
  const CommandLogState({
    this.lines = const [],
    this.running = false,
    this.finished = false,
    this.exitCode,
  });

  final List<CommandOutputLine> lines;
  final bool running;
  final bool finished;
  final int? exitCode;

  bool get isSuccess => finished && exitCode == 0;
  bool get isFailure => finished && exitCode != 0;

  CommandLogState copyWith({
    List<CommandOutputLine>? lines,
    bool? running,
    bool? finished,
    int? exitCode,
  }) {
    return CommandLogState(
      lines: lines ?? this.lines,
      running: running ?? this.running,
      finished: finished ?? this.finished,
      exitCode: exitCode ?? this.exitCode,
    );
  }

  @override
  List<Object?> get props => [lines, running, finished, exitCode];
}
