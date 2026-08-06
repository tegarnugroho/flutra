import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/device.dart';
import '../../domain/repositories/device_repository.dart';
import '../../domain/repositories/flutter_repository.dart';

part 'device_manager_state.dart';

/// Drives the Device Manager: lists devices and runs per-device actions.
@injectable
class DeviceManagerCubit extends Cubit<DeviceManagerState> {
  DeviceManagerCubit(this._repository, this._flutterRepository)
      : super(const DeviceManagerState());

  final DeviceRepository _repository;
  final FlutterRepository _flutterRepository;

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(status: DeviceManagerStatus.loading, clearError: true));
    try {
      final devices = await _combinedDevices();
      if (isClosed) return;
      emit(state.copyWith(status: DeviceManagerStatus.ready, devices: devices));
    } on Failure catch (e) {
      _emitFailure(e.message, e.suggestion);
    } catch (e) {
      _emitFailure('$e', null);
    }
  }

  /// Merges `adb devices` (rich Android info) with `flutter devices` (adds
  /// desktop/web targets). adb entries win for Android devices present in both.
  Future<List<Device>> _combinedDevices() async {
    final adb = await _repository.listDevices();
    List<Device> flutter;
    try {
      flutter = await _flutterRepository.listDevices();
    } on Failure {
      flutter = const []; // flutter missing shouldn't break the adb listing
    }

    final bySerial = {for (final d in adb) d.serial: d};
    for (final f in flutter) {
      // Skip Android devices adb already reported (adb has battery/version).
      if (bySerial.containsKey(f.serial)) continue;
      if (f.supportsAdb) continue; // an Android target adb didn't see — ignore
      bySerial[f.serial] = f;
    }

    final list = bySerial.values.toList()
      ..sort((a, b) {
        // Android devices first, then desktop/web.
        final byAdb = (b.supportsAdb ? 1 : 0) - (a.supportsAdb ? 1 : 0);
        return byAdb != 0 ? byAdb : a.displayName.compareTo(b.displayName);
      });
    return list;
  }

  Future<void> reboot(Device device, RebootTarget target) => _run(
    device.serial,
    DeviceTask.rebooting,
    () => _repository.reboot(device.serial, target),
  );

  Future<void> disconnect(Device device) => _run(
    device.serial,
    DeviceTask.disconnecting,
    () => _repository.disconnect(device),
  );

  Future<void> openShell(Device device) =>
      _fireAndForget(() => _repository.openShell(device.serial));

  Future<void> openLogcat(Device device) =>
      _fireAndForget(() => _repository.openLogcat(device.serial));

  /// Captures a screenshot; returns the saved path, or null on failure.
  Future<String?> screenshot(Device device) async {
    _task(device.serial, DeviceTask.capturing);
    try {
      return await _repository.screenshot(device.serial);
    } on Failure catch (e) {
      _reportError(
          '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
      return null;
    } finally {
      _task(device.serial, null);
    }
  }

  /// Starts an APK install; the caller streams the returned handle.
  Future<RunningCommand> installApk(Device device, String apkPath) =>
      _repository.installApk(device.serial, apkPath);

  // ---- helpers -------------------------------------------------------------

  Future<void> _run(
    String serial,
    DeviceTask task,
    Future<void> Function() action,
  ) async {
    _task(serial, task);
    try {
      await action();
      await load();
    } on Failure catch (e) {
      _reportError(
          '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _reportError('$e');
    } finally {
      _task(serial, null);
    }
  }

  Future<void> _fireAndForget(Future<void> Function() action) async {
    try {
      await action();
    } on Failure catch (e) {
      _reportError(e.message);
    } catch (e) {
      _reportError('$e');
    }
  }

  void _task(String serial, DeviceTask? task) {
    if (isClosed) return;
    final next = Map<String, DeviceTask>.from(state.tasks);
    if (task == null) {
      next.remove(serial);
    } else {
      next[serial] = task;
    }
    emit(state.copyWith(tasks: next));
  }

  void _reportError(String message) {
    if (isClosed) return;
    emit(state.copyWith(errorMessage: message));
  }

  void _emitFailure(String message, String? suggestion) {
    if (isClosed) return;
    emit(state.copyWith(
      status: DeviceManagerStatus.failure,
      errorMessage: '$message${suggestion == null ? '' : '\n$suggestion'}',
    ));
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
