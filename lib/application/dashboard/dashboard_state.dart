part of 'dashboard_cubit.dart';

/// Loading phase of the dashboard.
enum DashboardStatus { initial, loading, ready, failure }

/// Immutable UI state for the dashboard screen.
class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.snapshot,
    this.errorMessage,
    this.lastUpdated,
  });

  final DashboardStatus status;
  final EnvironmentSnapshot? snapshot;
  final String? errorMessage;
  final DateTime? lastUpdated;

  bool get isLoading => status == DashboardStatus.loading;

  DashboardState copyWith({
    DashboardStatus? status,
    EnvironmentSnapshot? snapshot,
    String? errorMessage,
    DateTime? lastUpdated,
  }) {
    return DashboardState(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      errorMessage: errorMessage,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  List<Object?> get props => [status, snapshot, errorMessage, lastUpdated];
}
