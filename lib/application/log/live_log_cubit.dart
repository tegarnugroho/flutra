import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/command/command_result.dart';
import '../../core/command/command_runner.dart';
import '../../domain/entities/log_line.dart';

part 'live_log_state.dart';

/// Streams a running command's output into a filterable, pausable log buffer.
///
/// Shared by the Logcat Viewer (parses logcat priorities) and the Emulator
/// Console (plain stdout/stderr). Created per-view, not registered in DI.
class LiveLogCubit extends Cubit<LiveLogState> {
  LiveLogCubit({required this.parseLogcat}) : super(const LiveLogState());

  /// When true, incoming lines are parsed as logcat (`I/Tag(pid): msg`).
  final bool parseLogcat;

  /// Hard cap on retained lines to bound memory on chatty streams.
  static const int _maxLines = 5000;

  RunningCommand? _command;
  StreamSubscription<CommandOutputLine>? _sub;
  final List<LogLine> _all = [];
  final List<LogLine> _pending = []; // buffered while paused

  /// Starts [starter] and streams its output. Replaces any current stream.
  Future<void> start(Future<RunningCommand> Function() starter) async {
    await stop();
    _all.clear();
    _pending.clear();
    emit(state.copyWith(
      status: LiveLogStatus.starting,
      lines: const [],
      clearError: true,
    ));
    try {
      final command = await starter();
      _command = command;
      emit(state.copyWith(status: LiveLogStatus.running));
      _sub = command.output.listen(_onLine);
      command.result.then((_) {
        if (!isClosed) emit(state.copyWith(status: LiveLogStatus.stopped));
      });
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
            status: LiveLogStatus.failure, errorMessage: '$e'));
      }
    }
  }

  void _onLine(CommandOutputLine line) {
    final parsed = parseLogcat
        ? LogLine.parseLogcat(line.text)
        : LogLine.plain(line.text, isError: line.isError);
    if (state.paused) {
      _pending.add(parsed);
      return;
    }
    _all.add(parsed);
    _trim();
    _emitLines();
  }

  void _trim() {
    if (_all.length > _maxLines) {
      _all.removeRange(0, _all.length - _maxLines);
    }
  }

  void _emitLines() {
    if (!isClosed) emit(state.copyWith(lines: List.unmodifiable(_all)));
  }

  void pause() => emit(state.copyWith(paused: true));

  void resume() {
    if (_pending.isNotEmpty) {
      _all.addAll(_pending);
      _pending.clear();
      _trim();
    }
    emit(state.copyWith(paused: false, lines: List.unmodifiable(_all)));
  }

  void clear() {
    _all.clear();
    _pending.clear();
    emit(state.copyWith(lines: const []));
  }

  void setQuery(String query) => emit(state.copyWith(query: query));

  void setUseRegex(bool value) => emit(state.copyWith(useRegex: value));

  void setTagFilter(String tag) => emit(state.copyWith(tagFilter: tag));

  void setMinPriority(LogPriority priority) =>
      emit(state.copyWith(minPriority: priority));

  /// Terminates the underlying process.
  Future<void> stop() async {
    _command?.cancel();
    await _sub?.cancel();
    _sub = null;
    _command = null;
  }

  @override
  Future<void> close() {
    _command?.cancel();
    _sub?.cancel();
    return super.close();
  }
}
