import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_result.dart';
import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/repositories/sdk_repository.dart';

part 'sdk_manager_state.dart';

/// Drives the Package Manager: catalogue, filters, multi-select, a sequential
/// install queue and a streamed sdkmanager console.
@injectable
class SdkManagerCubit extends Cubit<SdkManagerState> {
  SdkManagerCubit(this._repository) : super(const SdkManagerState());

  final SdkRepository _repository;

  static const int _maxConsole = 1000;
  static final RegExp _progressPattern = RegExp(r'(\d{1,3})\s*%');

  RunningCommand? _current;
  bool _cancelled = false;

  // ---- Catalogue -----------------------------------------------------------

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(status: SdkManagerStatus.loading, clearError: true));
    try {
      final packages = await _repository.listPackages();
      if (isClosed) return;
      emit(state.copyWith(status: SdkManagerStatus.ready, packages: packages));
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    }
  }

  // ---- Filters / view ------------------------------------------------------

  void setQuery(String query) => emit(state.copyWith(query: query));
  void setSort(PackageSort sort) => emit(state.copyWith(sort: sort));
  void setCategory(PackageCategory? category) =>
      emit(state.copyWith(category: category, clearCategory: category == null));
  void toggleUpdatesOnly(bool v) => emit(state.copyWith(updatesOnly: v));
  void toggleInstalledOnly(bool v) => emit(state.copyWith(installedOnly: v));
  void select(String path) => emit(state.copyWith(selectedPath: path));

  // ---- Multi-select --------------------------------------------------------

  void toggleCheck(String path) {
    final next = Set<String>.from(state.selected);
    next.contains(path) ? next.remove(path) : next.add(path);
    emit(state.copyWith(selected: next));
  }

  void checkAllVisible() {
    final next = Set<String>.from(state.selected)
      ..addAll(state.filtered.map((p) => p.path));
    emit(state.copyWith(selected: next));
  }

  void clearChecks() => emit(state.copyWith(selected: const {}));

  // ---- Console -------------------------------------------------------------

  void toggleConsole() =>
      emit(state.copyWith(consoleVisible: !state.consoleVisible));
  void clearConsole() => emit(state.copyWith(console: const []));

  void _log(String line) {
    final next = [...state.console, line];
    if (next.length > _maxConsole) {
      next.removeRange(0, next.length - _maxConsole);
    }
    if (!isClosed) emit(state.copyWith(console: next));
  }

  // ---- Operations ----------------------------------------------------------

  /// Queues [path] for installation/update.
  void enqueueInstall(String path) {
    if (state.isActive(path) || state.isQueued(path)) return;
    emit(state.copyWith(queue: [...state.queue, path]));
    _drainQueue();
  }

  /// Queues every checked package that can be installed/updated.
  void installSelected() {
    final targets = state.packages
        .where((p) =>
            state.selected.contains(p.path) &&
            (!p.isInstalled || p.hasUpdate))
        .map((p) => p.path)
        .where((p) => !state.isActive(p) && !state.isQueued(p))
        .toList();
    if (targets.isEmpty) return;
    emit(state.copyWith(queue: [...state.queue, ...targets]));
    _drainQueue();
  }

  /// Uninstalls every checked, installed package (sequentially).
  Future<void> removeSelected() async {
    final targets = state.packages
        .where((p) => state.selected.contains(p.path) && p.isInstalled)
        .map((p) => p.path)
        .toList();
    for (final path in targets) {
      if (_cancelled) break;
      await _runStreaming('--uninstall $path', () => _repository.uninstall(path),
          activePath: path);
    }
    await load();
  }

  /// Updates all installed packages via `sdkmanager --update`.
  Future<void> updateAll() async {
    // sdkmanager can't overwrite its own jars while running; tell the
    // repository when cmdline-tools is part of this batch so it can stage a
    // copy instead of paying that cost on every update.
    final touchesCmdlineTools = state.packages.any(
        (p) => p.hasUpdate && p.path.startsWith('cmdline-tools'));
    await _runStreaming(
      '--update',
      () => _repository.updateAll(includesCmdlineTools: touchesCmdlineTools),
    );
    await load();
  }

  /// Cancels the running operation and clears the queue.
  void cancel() {
    _cancelled = true;
    _current?.cancel();
    emit(state.copyWith(queue: const []));
  }

  /// Processes the install queue one package at a time.
  Future<void> _drainQueue() async {
    if (state.busy) return; // a worker is already running
    _cancelled = false;
    while (state.queue.isNotEmpty && !_cancelled) {
      final path = state.queue.first;
      emit(state.copyWith(queue: state.queue.sublist(1)));
      await _runStreaming(path, () => _repository.install(path),
          activePath: path);
    }
    if (!isClosed) await load(); // refresh statuses after the batch
  }

  /// Runs a streaming sdkmanager command, mirroring output to the console and
  /// parsing progress. [activePath] drives the per-package progress bar.
  Future<void> _runStreaming(
    String label,
    Future<RunningCommand> Function() start, {
    String? activePath,
  }) async {
    if (isClosed) return;
    emit(state.copyWith(
      busy: true,
      activePath: activePath,
      progress: activePath != null ? 0 : null,
      consoleVisible: true,
      clearError: true,
    ));
    _log('\$ sdkmanager $label');
    try {
      final command = await start();
      _current = command;
      final sub = command.output.listen(_onOutput);
      final result = await command.result;
      await sub.cancel();
      _log(result.isSuccess
          ? '✓ Done (exit ${result.exitCode})'
          : '✗ Failed (exit ${result.exitCode})');
      if (!result.isSuccess && !_cancelled) {
        _fail('sdkmanager failed for "$label" (exit ${result.exitCode}).');
      }
    } on Failure catch (e) {
      _log('✗ ${e.message}');
      _fail(e.message);
    } catch (e) {
      _log('✗ $e');
    } finally {
      _current = null;
      if (!isClosed) {
        emit(state.copyWith(busy: false, clearActive: true));
      }
    }
  }

  void _onOutput(CommandOutputLine line) {
    _log(line.text);
    if (state.activePath != null) {
      final match = _progressPattern.firstMatch(line.text);
      if (match != null) {
        final pct = int.tryParse(match.group(1)!) ?? 0;
        if (!isClosed) {
          emit(state.copyWith(progress: (pct.clamp(0, 100)) / 100));
        }
      }
    }
  }

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(
        status: state.packages.isEmpty
            ? SdkManagerStatus.failure
            : SdkManagerStatus.ready,
        errorMessage: message));
  }

  @override
  Future<void> close() {
    _current?.cancel();
    return super.close();
  }
}
