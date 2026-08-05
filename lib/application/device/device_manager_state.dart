part of 'device_manager_cubit.dart';

enum DeviceManagerStatus { initial, loading, ready, failure }

/// Immutable state for the Device Manager.
class DeviceManagerState extends Equatable {
  const DeviceManagerState({
    this.status = DeviceManagerStatus.initial,
    this.devices = const [],
    this.busySerials = const {},
    this.errorMessage,
  });

  final DeviceManagerStatus status;
  final List<Device> devices;

  /// Serials with an in-flight action, for per-row spinners.
  final Set<String> busySerials;

  final String? errorMessage;

  bool get isLoading => status == DeviceManagerStatus.loading;

  /// True until the first load settles, so a screen with no data yet shows its
  /// skeleton from the very first frame.
  ///
  /// `isLoading` alone is not enough: the cubit is created during the first
  /// build and its status is still `initial` while that frame renders, which
  /// would flash the centred empty state before the skeleton takes over.
  bool get isFirstLoad =>
      devices.isEmpty &&
      (status == DeviceManagerStatus.initial ||
          status == DeviceManagerStatus.loading);
  bool isBusy(String serial) => busySerials.contains(serial);
  int get onlineCount => devices.where((d) => d.state.isOnline).length;

  DeviceManagerState copyWith({
    DeviceManagerStatus? status,
    List<Device>? devices,
    Set<String>? busySerials,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DeviceManagerState(
      status: status ?? this.status,
      devices: devices ?? this.devices,
      busySerials: busySerials ?? this.busySerials,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, devices, busySerials, errorMessage];
}
