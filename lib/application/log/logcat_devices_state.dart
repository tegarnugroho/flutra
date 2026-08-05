part of 'logcat_devices_cubit.dart';

class LogcatDevicesState extends Equatable {
  const LogcatDevicesState({
    this.online = const [],
    this.serial,
    this.isLoading = false,
    this.hasLoaded = false,
  });

  /// Devices adb reports as online.
  final List<Device> online;

  /// The device whose log is being streamed.
  final String? serial;

  final bool isLoading;

  /// Set once a load has finished, successfully or not.
  final bool hasLoaded;

  /// True once a load has finished and found nothing.
  bool get isEmpty => hasLoaded && online.isEmpty && !isLoading;

  /// True until that first load settles — see the note on the other states'
  /// `isFirstLoad`: without it the first frame flashes the empty state.
  bool get isFirstLoad => online.isEmpty && !hasLoaded;

  LogcatDevicesState copyWith({
    List<Device>? online,
    String? serial,
    bool? isLoading,
    bool? hasLoaded,
  }) {
    return LogcatDevicesState(
      online: online ?? this.online,
      serial: serial ?? this.serial,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }

  @override
  List<Object?> get props => [online, serial, isLoading, hasLoaded];
}
