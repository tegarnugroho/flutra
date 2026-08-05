import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/device.dart';
import '../../domain/entities/environment_snapshot.dart';
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

  /// Loads the stat-card counts and whatever storage report is on disk.
  ///
  /// Cached storage renders instantly; a report older than a day refreshes
  /// quietly in the background so the numbers drift toward the truth without
  /// the user waiting for a disk walk.
  Future<void> loadOverview() async {
    if (isClosed) return;
    // Fired together: three tool invocations that have nothing to say to each
    // other, and a file read.
    final avdsFuture = _emulators.listAvds();
    final devicesFuture = _devices.listDevices();
    final packagesFuture = _sdk.listPackages();
    final cachedFuture = _storage.cached();

    final avds = await avdsFuture.catchError((_) => const []);
    final devices = await devicesFuture.catchError((_) => const []);
    final packages = await packagesFuture.catchError((_) => const []);
    final cached = await cachedFuture;
    if (isClosed) return;

    emit(state.copyWith(
      stats: DashboardStats(
        avdCount: avds.length,
        runningAvdCount: avds.where((a) => a.isRunning).length,
        updateCount: packages.where((p) => p.hasUpdate).length,
        deviceCount: devices.where((d) => d.state.isOnline).length,
      ),
      storage: cached,
    ));

    if (cached == null || _storage.isStale(cached)) {
      await analyzeStorage(silent: cached != null);
    }
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
      emit(
        DashboardState(
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
