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

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(status: EmulatorListStatus.loading, clearError: true));
    try {
      final avds = await _repository.listAvds();
      if (isClosed) return;
      emit(state.copyWith(status: EmulatorListStatus.ready, avds: avds));
    } on Failure catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        status: EmulatorListStatus.failure,
        errorMessage: '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}',
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        status: EmulatorListStatus.failure,
        errorMessage: '$e',
      ));
    }
  }

  /// Launches [avd]; the running emulator process is fire-and-forget here (the
  /// Emulator Console screen can attach to its output separately).
  Future<void> launch(Avd avd, {LaunchOptions? options}) async {
    _busy(avd.name, true);
    try {
      await _repository.launch(avd.name, options ?? const LaunchOptions());
      // Give the process a moment to register with adb, then refresh state.
      await Future<void>.delayed(const Duration(seconds: 2));
      await load();
    } on Failure catch (e) {
      _fail(e.message);
    } finally {
      _busy(avd.name, false);
    }
  }

  Future<void> stop(Avd avd) => _run(avd.name, () => _repository.stop(avd.name));

  Future<void> wipe(Avd avd) =>
      _run(avd.name, () => _repository.wipeData(avd.name));

  Future<void> delete(Avd avd) =>
      _run(avd.name, () => _repository.deleteAvd(avd.name));

  Future<void> duplicate(Avd avd, String newName) =>
      _run(avd.name, () => _repository.duplicateAvd(avd.name, newName));

  Future<void> _run(String name, Future<void> Function() action) async {
    _busy(name, true);
    try {
      await action();
      await load();
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    } finally {
      _busy(name, false);
    }
  }

  void _busy(String name, bool busy) {
    if (isClosed) return;
    final next = Set<String>.from(state.busyNames);
    busy ? next.add(name) : next.remove(name);
    emit(state.copyWith(busyNames: next));
  }

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(errorMessage: message, status: state.status));
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
