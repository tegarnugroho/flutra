import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/device.dart';
import '../../domain/repositories/device_repository.dart';

part 'logcat_devices_state.dart';

/// Holds the online-device list and the selected serial for the Logcat screen.
///
/// The list is fetched from adb, so it belongs in a cubit rather than in widget
/// state — the page rebuilds far more often than the devices change.
@injectable
class LogcatDevicesCubit extends Cubit<LogcatDevicesState> {
  LogcatDevicesCubit(this._devices) : super(const LogcatDevicesState());

  final DeviceRepository _devices;

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true));
    try {
      final all = await _devices.listDevices();
      if (isClosed) return;
      final online = all.where((d) => d.state.isOnline).toList();
      // Keep the current selection when it is still connected.
      final keep = online.any((d) => d.serial == state.serial);
      emit(LogcatDevicesState(
        online: online,
        serial: keep ? state.serial : (online.isEmpty ? null : online.first.serial),
      ));
    } catch (_) {
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }

  void select(String serial) {
    if (isClosed || serial == state.serial) return;
    emit(state.copyWith(serial: serial));
  }
}
