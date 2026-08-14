import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_result.dart';
import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../../infrastructure/sdk/sdk_bootstrap_service.dart';
import '../../infrastructure/sdk/sdk_locator.dart';
import '../settings/settings_cubit.dart';
import '../toolchain_events.dart';

part 'sdk_manager_state.dart';

/// Drives the Package Manager: catalogue, filters, multi-select, a sequential
/// install queue and a streamed sdkmanager console.
@injectable
class SdkManagerCubit extends Cubit<SdkManagerState> {
  SdkManagerCubit(
    this._repository,
    this._locator,
    this._bootstrap,
    this._settings,
    this._toolchain,
  ) : super(const SdkManagerState());

  final SdkRepository _repository;

  /// Consulted only to tell the failure cases apart — see [classifySdkFailure].
  /// The catalogue itself still comes from [SdkRepository].
  final SdkLocator _locator;
  final SdkBootstrapService _bootstrap;
  final SettingsCubit _settings;
  final ToolchainEvents _toolchain;

  /// What a new SDK gets before it is any use.
  ///
  /// platform-tools is the floor rather than a preference: it carries `adb`,
  /// which every device list, every install and the Dashboard's ADB row need.
  static const List<String> baselinePackages = ['platform-tools'];

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
      emit(state.copyWith(
        status: SdkManagerStatus.ready,
        packages: packages,
        availability: SdkAvailability.ok,
      ));
    } on Failure catch (e) {
      _fail(
        '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}',
        detail: e is ProcessFailure ? e.output : null,
      );
    } catch (e) {
      _fail('$e');
    }
  }

  // ---- First-run bootstrap -------------------------------------------------

  /// Creates an Android SDK where there is none, or completes a half-installed
  /// one.
  ///
  /// Runs to [SdkBootstrapStage.awaitingLicences] and stops there. The licences
  /// are Google's terms for the packages that come next, so the flow pauses to
  /// show them rather than answering them quietly on the user's behalf —
  /// [acceptLicencesAndFinish] is the other half.
  Future<void> bootstrapSdk() async {
    if (isClosed || state.isBootstrapping) return;
    emit(state.copyWith(
      bootstrap: const SdkBootstrapEvent(
        stage: SdkBootstrapStage.downloading,
        progress: 0,
      ),
      consoleVisible: true,
      clearError: true,
    ));
    // A half-installed SDK gets the tools added to it. Creating a second SDK
    // beside the first would leave the machine with two and the user with a
    // choice they never asked to make.
    final existing = state.availability == SdkAvailability.sdkFoundNoCmdlineTools
        ? _locator.sdkRoot
        : null;
    _log('\$ bootstrap android-sdk${existing == null ? '' : ' into $existing'}');

    await for (final event
        in _bootstrap.installCommandLineTools(intoSdkRoot: existing)) {
      if (isClosed) return;
      emit(state.copyWith(bootstrap: event));
      if (event.stage == SdkBootstrapStage.failed) {
        _log('✗ ${event.error ?? 'bootstrap failed'}');
        return;
      }
      if (event.stage == SdkBootstrapStage.awaitingLicences) {
        // The tools are on disk and usable from here on, so the path is saved
        // now rather than after the packages: if the user closes the app at the
        // licence step, what they already downloaded is not lost.
        await _adoptSdkRoot(event.sdkRoot!);
        _log('✓ command-line tools installed in ${event.sdkRoot}');
        return;
      }
    }
  }

  /// Accepts the SDK licences, installs the baseline packages, and reloads.
  ///
  /// Only reachable from the licence step, which is the point: this is the call
  /// the user's click authorises.
  Future<void> acceptLicencesAndFinish() async {
    if (isClosed || !state.awaitingLicences) return;
    final sdkRoot = state.bootstrap!.sdkRoot;

    emit(state.copyWith(
      bootstrap: SdkBootstrapEvent(
        stage: SdkBootstrapStage.installingPackages,
        sdkRoot: sdkRoot,
      ),
      clearError: true,
    ));
    await _runStreaming('--licenses', _repository.acceptAllLicenses);
    for (final package in baselinePackages) {
      if (isClosed || _cancelled) break;
      await _runStreaming(package, () => _repository.install(package),
          activePath: package);
    }
    if (isClosed) return;

    // _runStreaming reports a failure by setting errorMessage. Without this the
    // page would keep rendering the progress view, which has no end state and
    // no way out — the same dead end this whole flow exists to remove.
    final failure = state.errorMessage;
    if (failure != null) {
      emit(state.copyWith(
        bootstrap: SdkBootstrapEvent(
          stage: SdkBootstrapStage.failed,
          error: failure,
          // Carried so the failure screen knows the hard part already
          // succeeded: the tools are on disk and the path is saved, so the way
          // out is re-reading the catalogue, not downloading 130 MB again.
          sdkRoot: sdkRoot,
        ),
      ));
      return;
    }

    emit(state.copyWith(
      bootstrap: const SdkBootstrapEvent(stage: SdkBootstrapStage.done),
    ));
    // adb exists now, so the Dashboard's Android SDK and ADB rows are both
    // wrong until they are told.
    _toolchain.emitChanged();
    await load();
    if (!isClosed) emit(state.copyWith(clearBootstrap: true));
  }

  /// Adopts an SDK the user already has.
  ///
  /// Returns null when it was accepted, or why it was rejected. The same test
  /// the rest of the app uses — a folder called `Sdk` with nothing in it is a
  /// folder, and accepting it would move the dead end one screen along.
  Future<String?> useExistingSdk(String directory) async {
    final path = directory.trim();
    if (path.isEmpty) return 'No folder was chosen.';
    if (!Directory(path).existsSync()) {
      return '"$path" does not exist.';
    }
    if (!SdkLocator.looksLikeAndroidSdk(path)) {
      return '"$path" does not hold the Android tools. Pick the SDK root — the '
          'folder containing platform-tools, platforms or cmdline-tools.';
    }
    await _adoptSdkRoot(path);
    await load();
    return null;
  }

  /// Points settings — and so the whole app — at [root], and says so.
  Future<void> _adoptSdkRoot(String root) async {
    await _settings.setAndroidSdkPath(root);
    _toolchain.emitChanged();
  }

  /// Stops a bootstrap in flight.
  void cancelBootstrap() {
    _bootstrap.cancel();
    if (!isClosed) emit(state.copyWith(clearBootstrap: true));
  }

  /// Clears a failed bootstrap's message once it has been read.
  void dismissBootstrap() {
    if (!isClosed) emit(state.copyWith(clearBootstrap: true));
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

  void _fail(String message, {String? detail}) {
    if (isClosed) return;
    final empty = state.packages.isEmpty;
    emit(state.copyWith(
      status: empty ? SdkManagerStatus.failure : SdkManagerStatus.ready,
      errorMessage: message,
      errorDetail: detail,
      // Only a failure with nothing to show is a state the page has to offer a
      // way out of; a failed install on a loaded catalogue is just a message.
      availability: empty
          ? classifySdkFailure(
              hasSdkRoot: _locator.sdkRoot != null,
              hasSdkManager: _locator.sdkManager != null,
            )
          : SdkAvailability.ok,
    ));
  }

  @override
  Future<void> close() {
    _current?.cancel();
    return super.close();
  }
}
