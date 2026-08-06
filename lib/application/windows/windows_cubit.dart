import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/error/failures.dart';
import '../../domain/entities/windows_toolchain.dart';
import '../../infrastructure/windows/windows_toolchain_service.dart';

part 'windows_state.dart';

/// Drives the Windows screen: what the build toolchain is, and fixing it.
@injectable
class WindowsCubit extends Cubit<WindowsState> {
  WindowsCubit(this._service) : super(const WindowsState());

  final WindowsToolchainService _service;

  Future<void> load({bool force = false}) async {
    if (isClosed) return;
    emit(state.copyWith(status: WindowsStatus.loading, clearError: true));
    try {
      if (force) _service.refresh();
      final toolchain = await _service.detect(force: force);
      if (isClosed) return;
      emit(state.copyWith(
        status: WindowsStatus.ready,
        toolchain: toolchain,
      ));
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    }
  }

  /// Installs Build Tools with the C++ workload, from nothing.
  Future<void> installBuildTools() =>
      _setup(_service.installBuildTools());

  Future<void> addCppTools(VisualStudioInstall install) =>
      _setup(_service.addCppTools(install));

  Future<void> update(VisualStudioInstall install) =>
      _setup(_service.update(install));

  Future<void> repair(VisualStudioInstall install) =>
      _setup(_service.repair(install));

  /// Runs one installer to completion.
  ///
  /// Only one at a time: Microsoft's installer holds a machine-wide lock, and a
  /// second run would fail with an error about the first.
  Future<void> _setup(Stream<WindowsSetupEvent> events) async {
    if (isClosed || state.isBusy) return;
    await for (final event in events) {
      if (isClosed) return;
      emit(state.copyWith(setup: event));
      if (event.stage == WindowsSetupStage.done) {
        // The installer changed the machine; the page must re-read it.
        await load(force: true);
        return;
      }
      if (event.stage == WindowsSetupStage.failed) return;
    }
  }

  /// Clears the last setup result once it has been read.
  void dismissSetup() => emit(state.copyWith(clearSetup: true));

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(status: WindowsStatus.failure, errorMessage: message));
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
