part of 'emulator_list_cubit.dart';

enum EmulatorListStatus { initial, loading, ready, failure }

/// The operation a device is in the middle of, which is what its button says
/// while it runs.
enum AvdTask {
  starting,
  stopping,
  wiping,
  deleting,
  duplicating,
  renaming;

  /// Present tense, for the in-flight button label.
  String get label => switch (this) {
    AvdTask.starting => 'Starting…',
    AvdTask.stopping => 'Stopping…',
    AvdTask.wiping => 'Wiping…',
    AvdTask.deleting => 'Deleting…',
    AvdTask.duplicating => 'Duplicating…',
    AvdTask.renaming => 'Renaming…',
  };
}

/// Immutable state for the Emulator Manager list.
class EmulatorListState extends Equatable {
  const EmulatorListState({
    this.status = EmulatorListStatus.initial,
    this.avds = const [],
    this.tasks = const {},
    this.errorMessage,
  });

  final EmulatorListStatus status;

  /// AVDs in display order: running first, then by name — see
  /// [EmulatorListCubit.load], which is the only thing that reorders them.
  final List<Avd> avds;

  /// The in-flight operation per AVD name, for spinners and labels.
  final Map<String, AvdTask> tasks;

  final String? errorMessage;

  bool get isLoading => status == EmulatorListStatus.loading;

  /// True until the first load settles, so a screen with no data yet shows its
  /// skeleton from the very first frame.
  ///
  /// `isLoading` alone is not enough: the cubit is created during the first
  /// build and its status is still `initial` while that frame renders, which
  /// would flash the centred empty state before the skeleton takes over.
  bool get isFirstLoad =>
      avds.isEmpty &&
      (status == EmulatorListStatus.initial ||
          status == EmulatorListStatus.loading);

  bool isBusy(String name) => tasks.containsKey(name);

  AvdTask? taskFor(String name) => tasks[name];

  int get runningCount => avds.where((a) => a.isRunning).length;

  /// `4 devices · 1 running`. The running segment is dropped when there is
  /// none, rather than reading "· 0 running".
  String get countLabel {
    final devices = '${avds.length} device${avds.length == 1 ? '' : 's'}';
    return runningCount == 0 ? devices : '$devices · $runningCount running';
  }

  EmulatorListState copyWith({
    EmulatorListStatus? status,
    List<Avd>? avds,
    Map<String, AvdTask>? tasks,
    String? errorMessage,
    bool clearError = false,
  }) {
    return EmulatorListState(
      status: status ?? this.status,
      avds: avds ?? this.avds,
      tasks: tasks ?? this.tasks,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, avds, tasks, errorMessage];
}
