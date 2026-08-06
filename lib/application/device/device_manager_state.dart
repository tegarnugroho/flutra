part of 'device_manager_cubit.dart';

enum DeviceManagerStatus { initial, loading, ready, failure }

/// The action a device is in the middle of, which is what its button says
/// while it runs.
enum DeviceTask {
  capturing,
  rebooting,
  disconnecting;

  String get label => switch (this) {
    DeviceTask.capturing => 'Capturing…',
    DeviceTask.rebooting => 'Rebooting…',
    DeviceTask.disconnecting => 'Disconnecting…',
  };
}

/// Immutable state for the Device Manager.
class DeviceManagerState extends Equatable {
  const DeviceManagerState({
    this.status = DeviceManagerStatus.initial,
    this.devices = const [],
    this.tasks = const {},
    this.errorMessage,
  });

  final DeviceManagerStatus status;
  final List<Device> devices;

  /// The in-flight action per serial, for spinners and labels.
  final Map<String, DeviceTask> tasks;

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
  bool isBusy(String serial) => tasks.containsKey(serial);

  DeviceTask? taskFor(String serial) => tasks[serial];

  int get onlineCount => devices.where((d) => d.state.isOnline).length;

  /// `3 devices · 1 offline`. Online is the normal state, so it is the ones
  /// that are *not* usable that the count calls out.
  String get countLabel {
    final total = '${devices.length} device${devices.length == 1 ? '' : 's'}';
    final offline = devices.length - onlineCount;
    return offline == 0 ? total : '$total · $offline offline';
  }

  DeviceManagerState copyWith({
    DeviceManagerStatus? status,
    List<Device>? devices,
    Map<String, DeviceTask>? tasks,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DeviceManagerState(
      status: status ?? this.status,
      devices: devices ?? this.devices,
      tasks: tasks ?? this.tasks,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, devices, tasks, errorMessage];
}
