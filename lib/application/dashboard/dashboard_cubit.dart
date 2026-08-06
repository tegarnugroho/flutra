import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/avd.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/environment_snapshot.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/entities/storage_report.dart';
import '../../domain/repositories/device_repository.dart';
import '../../domain/repositories/emulator_repository.dart';
import '../../domain/repositories/environment_repository.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../../infrastructure/storage/storage_analysis_service.dart';

part 'dashboard_state.dart';

/// Drives the dashboard: detects the toolchain and exposes its status.
@injectable
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(
    this._repository,
    this._emulators,
    this._devices,
    this._sdk,
    this._storage,
  ) : super(const DashboardState());

  final EnvironmentRepository _repository;
  final EmulatorRepository _emulators;
  final DeviceRepository _devices;
  final SdkRepository _sdk;
  final StorageAnalysisService _storage;

  /// The screen's startup load, in the order the user sees things.
  ///
  /// Sequential on purpose. Every tool invocation is a `Process.start`, and on
  /// Windows each one blocks this isolate for ~1.2ms while the OS spawns it (a
  /// shell included). Firing the detection probes and the overview tools
  /// together — 9 spawns at once — stalls the event loop for 32-75ms, which is
  /// 2-5 dropped frames at 60Hz and lands exactly while the skeleton shimmer is
  /// starting. Measured lag drops to 5-6ms when the same 9 are spread out.
  ///
  /// Detection comes first because the skeleton is up until [state.snapshot]
  /// arrives: the stat counts are invisible before that, however early they
  /// land.
  Future<void> load({bool forceRefresh = false}) async {
    await refresh(forceRefresh: forceRefresh);
    if (isClosed) return;
    await loadOverview();
  }

  /// Loads the stat-card counts and whatever storage report is on disk.
  ///
  /// Cached storage renders instantly; a report older than a day refreshes
  /// quietly in the background so the numbers drift toward the truth without
  /// the user waiting for a disk walk.
  Future<void> loadOverview() async {
    if (isClosed) return;

    // The cached report is one file read, so it settles long before any tool
    // does. Publishing it — and the fact that a scan is coming — before the
    // slow calls is what stops the panel from sitting on "No scan yet" for a
    // couple of seconds and then producing figures out of nowhere.
    final cached = await _storage.cached();
    if (isClosed) return;
    final willScan = cached == null || _storage.isStale(cached);
    // Only say "busy" when there is nothing to look at. A stale report keeps
    // its numbers on screen and refreshes underneath, as before.
    final showBusy = cached == null;
    emit(state.copyWith(storage: cached, scanning: showBusy));

    // The scan is an isolate, not a process, so it costs none of the spawn
    // stall the tools below do and can run alongside them instead of queueing
    // behind the slowest one.
    final scan = willScan ? analyzeStorage(silent: !showBusy) : null;

    // Two waves rather than one: see [load] for why concurrent spawns cost
    // frames. adb and avdmanager are the cheap pair and feed three of the four
    // stat cards; sdkmanager --list is the slow one and follows on its own.
    final avdsFuture = _emulators.listAvds();
    final devicesFuture = _devices.listDevices();

    // A tool that fails contributes a zero rather than sinking the whole
    // overview — the toolchain list above already reports what is broken.
    final avds = await avdsFuture.catchError((_) => const <Avd>[]);
    final devices = await devicesFuture.catchError((_) => const <Device>[]);
    if (isClosed) return;

    final packages = await _sdk.listPackages().catchError(
      (_) => const <SdkPackage>[],
    );
    if (isClosed) return;

    emit(state.copyWith(
      stats: DashboardStats(
        avdCount: avds.length,
        runningAvdCount: avds.where((a) => a.isRunning).length,
        updateCount: packages.where((p) => p.hasUpdate).length,
        deviceCount: devices.where((d) => d.state.isOnline).length,
      ),
    ));

    await scan;
  }

  /// Walks the disk. [silent] keeps the existing report on screen instead of
  /// showing the panel as busy — used for the stale-cache refresh.
  Future<void> analyzeStorage({bool silent = false}) async {
    if (isClosed) return;
    if (!silent) emit(state.copyWith(scanning: true));
    try {
      final report = await _storage.analyze();
      if (isClosed) return;
      emit(state.copyWith(storage: report, scanning: false));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(scanning: false));
    }
  }

  /// Runs (or re-runs) toolchain detection.
  ///
  /// [forceRefresh] is what the header Refresh button sends: it also bypasses
  /// the cached Flutter release index.
  Future<void> refresh({bool forceRefresh = false}) async {
    // Detection outlives the page: leaving the Dashboard closes this cubit
    // while the probe is still running, and emitting then throws.
    if (isClosed) return;
    emit(state.copyWith(status: DashboardStatus.loading));
    try {
      final snapshot = await _repository.detect(forceRefresh: forceRefresh);
      if (isClosed) return;
      // copyWith, not a fresh state: detection and loadOverview run
      // concurrently, and a whole-state emit here drops the stat-card counts
      // that landed first — leaving their skeleton up for good.
      emit(
        state.copyWith(
          status: DashboardStatus.ready,
          snapshot: snapshot,
          lastUpdated: DateTime.now(),
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: DashboardStatus.failure,
          errorMessage: 'Detection failed: $e',
        ),
      );
    }
  }
}
