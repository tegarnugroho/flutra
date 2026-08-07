import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/error/failures.dart';
import '../../domain/entities/windows_toolchain.dart';
import '../../infrastructure/windows/windows_toolchain_service.dart';

part 'windows_state.dart';

/// Drives the Windows toolchain screen: what is missing, and running the
/// official installer that fixes it.
@injectable
class WindowsCubit extends Cubit<WindowsState> {
  WindowsCubit(this._service) : super(const WindowsState());

  final WindowsToolchainService _service;

  /// Returning from the VS Installer or from Settings fires focus events in
  /// bursts; one re-scan is enough.
  static const _focusDebounce = Duration(milliseconds: 600);

  Timer? _debounce;

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }

  Future<void> load({bool force = false}) async {
    if (isClosed) return;
    emit(state.copyWith(status: WindowsStatus.loading, clearError: true));
    try {
      if (force) _service.refresh();
      final toolchain = await _service.detect(force: force);
      if (isClosed) return;
      emit(state.copyWith(status: WindowsStatus.ready, toolchain: toolchain));
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    }
  }

  /// Re-reads after the window comes back, debounced.
  ///
  /// The user left to click through Microsoft's installer or to flip a switch
  /// in Settings; coming back is the signal that something may have changed.
  void refreshOnFocus() {
    if (isClosed || state.isBusy) return;
    _debounce?.cancel();
    _debounce = Timer(_focusDebounce, () {
      if (!isClosed) load(force: true);
    });
  }

  /// Runs whatever [requirement] says would fix it.
  ///
  /// Returns false when the action needs a confirmation the page has not
  /// shown yet — every installer launch does, and the page owns that dialog.
  Future<void> runAction(WindowsRequirement requirement) async {
    final toolchain = state.toolchain;
    switch (requirement.action) {
      case WindowsRequirementAction.none:
        return;
      case WindowsRequirementAction.installBuildTools:
        await _setup(_service.installBuildTools());
      case WindowsRequirementAction.addCppWorkload:
        final target = toolchain.installs.firstOrNull;
        if (target != null) await _setup(_service.addCppWorkload(target));
      case WindowsRequirementAction.addWindowsSdk:
        // The SDK rides on the install that owns the compiler.
        final target = toolchain.active ?? toolchain.installs.firstOrNull;
        if (target != null) await _setup(_service.addWindowsSdk(target));
      case WindowsRequirementAction.repair:
        final target = toolchain.active ?? toolchain.installs.firstOrNull;
        if (target != null) await _setup(_service.repair(target));
      case WindowsRequirementAction.openDeveloperSettings:
        await _service.openDeveloperModeSettings();
      case WindowsRequirementAction.enableWindowsDesktop:
        await _enableWindowsDesktop();
    }
  }

  /// Updates an install to the newest build Microsoft ships.
  Future<void> update(VisualStudioInstall install) =>
      _setup(_service.update(install));

  Future<void> _enableWindowsDesktop() async {
    if (isClosed || state.isBusy) return;
    emit(state.copyWith(pending: WindowsRequirementKind.flutterConfig));
    try {
      await _service.enableWindowsDesktop();
      await load(force: true);
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    } finally {
      if (!isClosed) emit(state.copyWith(clearPending: true));
    }
  }

  /// Runs one installer to completion.
  ///
  /// Only one at a time: Microsoft's installer holds a machine-wide lock, and
  /// a second run fails with an error about the first.
  Future<void> _setup(Stream<WindowsSetupEvent> events) async {
    if (isClosed || state.isBusy) return;
    await for (final event in events) {
      if (isClosed) return;
      emit(state.copyWith(setup: event));
      if (event.stage.isTerminal) {
        if (event.stage != WindowsSetupStage.failed) {
          // The installer changed the machine; the page must re-read it.
          await load(force: true);
        }
        return;
      }
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
