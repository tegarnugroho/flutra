part of 'logcat_devices_cubit.dart';

class LogcatDevicesState extends Equatable {
  const LogcatDevicesState({
    this.online = const [],
    this.serial,
    this.isLoading = false,
  });

  /// Devices adb reports as online.
  final List<Device> online;

  /// The device whose log is being streamed.
  final String? serial;

  final bool isLoading;

  /// True once a load has finished and found nothing.
  bool get isEmpty => online.isEmpty && !isLoading;

  LogcatDevicesState copyWith({
    List<Device>? online,
    String? serial,
    bool? isLoading,
  }) {
    return LogcatDevicesState(
      online: online ?? this.online,
      serial: serial ?? this.serial,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [online, serial, isLoading];
}
