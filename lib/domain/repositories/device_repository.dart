import '../../core/command/command_runner.dart';
import '../entities/device.dart';

/// Manages connected devices and emulators via `adb`.
abstract class DeviceRepository {
  /// Lists connected devices, enriched with model/version/battery info.
  Future<List<Device>> listDevices();

  /// Reboots [serial] into the given [target].
  Future<void> reboot(String serial, RebootTarget target);

  /// Installs (reinstalling if present) the APK at [apkPath] onto [serial].
  /// Returns the live process so the UI can stream progress.
  Future<RunningCommand> installApk(String serial, String apkPath);

  /// Captures a screenshot from [serial] and returns the saved file path.
  Future<String> screenshot(String serial);

  /// Disconnects a network device, or kills a running emulator.
  Future<void> disconnect(Device device);

  /// Opens an external terminal running `adb shell` for [serial].
  Future<void> openShell(String serial);

  /// Opens an external terminal running `adb logcat` for [serial].
  Future<void> openLogcat(String serial);

  /// Streams `adb logcat` for [serial] into the app. Returns the live process
  /// so the UI can display, filter and stop it. Clears the buffer first.
  Future<RunningCommand> streamLogcat(String serial);
}
