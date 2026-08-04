part of 'flutter_update_cubit.dart';

enum FlutterUpdateCheckStatus {
  initial,
  loading,

  /// The check completed and [FlutterUpdateState.update] is set.
  ready,

  /// No SDK, or the release index could not be reached.
  unavailable,
}

class FlutterUpdateState extends Equatable {
  const FlutterUpdateState({
    this.status = FlutterUpdateCheckStatus.initial,
    this.update,
  });

  final FlutterUpdateCheckStatus status;
  final FlutterUpdateStatus? update;

  bool get isLoading =>
      status == FlutterUpdateCheckStatus.initial ||
      status == FlutterUpdateCheckStatus.loading;

  @override
  List<Object?> get props => [status, update];
}
