part of 'emulator_list_cubit.dart';

enum EmulatorListStatus { initial, loading, ready, failure }

/// Immutable state for the Emulator Manager list.
class EmulatorListState extends Equatable {
  const EmulatorListState({
    this.status = EmulatorListStatus.initial,
    this.avds = const [],
    this.busyNames = const {},
    this.errorMessage,
  });

  final EmulatorListStatus status;
  final List<Avd> avds;

  /// AVD names with an in-flight operation (launch/wipe/delete), for spinners.
  final Set<String> busyNames;

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
  bool isBusy(String name) => busyNames.contains(name);

  EmulatorListState copyWith({
    EmulatorListStatus? status,
    List<Avd>? avds,
    Set<String>? busyNames,
    String? errorMessage,
    bool clearError = false,
  }) {
    return EmulatorListState(
      status: status ?? this.status,
      avds: avds ?? this.avds,
      busyNames: busyNames ?? this.busyNames,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, avds, busyNames, errorMessage];
}
