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
    this.stats,
    this.storage,
    this.scanning = false,
  });

  final DashboardStatus status;
  final EnvironmentSnapshot? snapshot;
  final String? errorMessage;
  final DateTime? lastUpdated;

  /// Counts behind the stat cards. Null until the first read completes.
  final DashboardStats? stats;

  /// The last disk scan, cached or fresh. Null before anything has been
  /// scanned — the panel then offers to run one.
  final StorageReport? storage;

  /// True while a scan is walking the disk.
  final bool scanning;

  bool get isLoading => status == DashboardStatus.loading;

  DashboardState copyWith({
    DashboardStatus? status,
    EnvironmentSnapshot? snapshot,
    String? errorMessage,
    DateTime? lastUpdated,
    DashboardStats? stats,
    StorageReport? storage,
    bool? scanning,
  }) {
    return DashboardState(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      errorMessage: errorMessage,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      stats: stats ?? this.stats,
      storage: storage ?? this.storage,
      scanning: scanning ?? this.scanning,
    );
  }

  @override
  List<Object?> get props => [
    status,
    snapshot,
    errorMessage,
    lastUpdated,
    stats,
    storage,
    scanning,
  ];
}

/// The numbers behind the four stat cards.
///
/// Read once through the shared repositories rather than by standing up the
/// other screens' cubits — those are factories, so a copy here would mean a
/// second round of adb and sdkmanager calls.
class DashboardStats extends Equatable {
  const DashboardStats({
    this.avdCount = 0,
    this.runningAvdCount = 0,
    this.updateCount = 0,
    this.deviceCount = 0,
  });

  final int avdCount;
  final int runningAvdCount;
  final int updateCount;
  final int deviceCount;

  @override
  List<Object?> get props => [
    avdCount,
    runningAvdCount,
    updateCount,
    deviceCount,
  ];
}
