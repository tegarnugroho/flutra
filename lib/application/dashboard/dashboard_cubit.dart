import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/environment_snapshot.dart';
import '../../domain/repositories/environment_repository.dart';

part 'dashboard_state.dart';

/// Drives the dashboard: detects the toolchain and exposes its status.
@injectable
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repository) : super(const DashboardState());

  final EnvironmentRepository _repository;

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
