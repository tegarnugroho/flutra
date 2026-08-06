import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/error/failures.dart';
import '../../domain/entities/avd.dart';
import '../../domain/entities/avd_create_request.dart';
import '../../domain/repositories/emulator_repository.dart';

part 'emulator_list_state.dart';

/// Drives the Emulator Manager list: load AVDs, launch, wipe, delete, etc.
@injectable
class EmulatorListCubit extends Cubit<EmulatorListState> {
  EmulatorListCubit(this._repository) : super(const EmulatorListState());

  final EmulatorRepository _repository;

  /// The order the list is currently drawn in, by AVD name.
  ///
  /// Held so a reload triggered by an action does not reshuffle the list under
  /// the pointer: starting a device makes it sort first, and a tile that moves
  /// out from under the cursor mid-click is how the wrong device gets stopped.
  List<String> _order = const [];

  /// Reads the AVDs.
  ///
  /// [resort] puts running devices first and the rest in name order. The page
  /// and the Refresh button ask for that; the reload after start/stop does not,
  /// keeping the list where the user left it until they ask for a fresh one.
  Future<void> load({bool resort = true}) async {
    if (isClosed) return;
    emit(state.copyWith(status: EmulatorListStatus.loading, clearError: true));
    try {
      final avds = await _repository.listAvds();
      if (isClosed) return;
      emit(state.copyWith(
        status: EmulatorListStatus.ready,
        avds: _ordered(avds, resort: resort),
      ));
    } on Failure catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        status: EmulatorListStatus.failure,
        errorMessage:
            '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}',
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        status: EmulatorListStatus.failure,
        errorMessage: '$e',
      ));
    }
  }

  /// Running first, then by name — or the order already on screen, with AVDs
  /// that appeared since (a duplicate, one created in the other window) sorted
  /// onto the end.
  List<Avd> _ordered(List<Avd> avds, {required bool resort}) {
    if (resort || _order.isEmpty) {
      final sorted = [...avds]..sort(_byRunningThenName);
      _order = [for (final avd in sorted) avd.name];
      return sorted;
    }
    final remaining = {for (final avd in avds) avd.name: avd};
    final kept = <Avd>[
      for (final name in _order)
        if (remaining.containsKey(name)) remaining.remove(name)!,
    ];
    final added = remaining.values.toList()..sort(_byRunningThenName);
    final result = [...kept, ...added];
    _order = [for (final avd in result) avd.name];
    return result;
  }

  static int _byRunningThenName(Avd a, Avd b) {
    if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Launches [avd]; the running emulator process is fire-and-forget here (the
  /// Emulator Console screen can attach to its output separately).
  Future<void> launch(Avd avd, {LaunchOptions? options}) async {
    _task(avd.name, AvdTask.starting);
    try {
      await _repository.launch(avd.name, options ?? const LaunchOptions());
      // Give the process a moment to register with adb, then refresh state.
      await Future<void>.delayed(const Duration(seconds: 2));
      await load(resort: false);
    } on Failure catch (e) {
      _fail(e.message);
    } finally {
      _task(avd.name, null);
    }
  }

  Future<void> stop(Avd avd) =>
      _run(avd.name, AvdTask.stopping, () => _repository.stop(avd.name));

  Future<void> wipe(Avd avd) =>
      _run(avd.name, AvdTask.wiping, () => _repository.wipeData(avd.name));

  Future<void> delete(Avd avd) =>
      _run(avd.name, AvdTask.deleting, () => _repository.deleteAvd(avd.name));

  Future<void> duplicate(Avd avd, String newName) => _run(
    avd.name,
    AvdTask.duplicating,
    () => _repository.duplicateAvd(avd.name, newName),
  );

  Future<void> _run(
    String name,
    AvdTask task,
    Future<void> Function() action,
  ) async {
    _task(name, task);
    try {
      await action();
      await load(resort: false);
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    } finally {
      _task(name, null);
    }
  }

  void _task(String name, AvdTask? task) {
    if (isClosed) return;
    final next = Map<String, AvdTask>.from(state.tasks);
    if (task == null) {
      next.remove(name);
    } else {
      next[name] = task;
    }
    emit(state.copyWith(tasks: next));
  }

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(errorMessage: message, status: state.status));
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
