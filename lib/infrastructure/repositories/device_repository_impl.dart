import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/device.dart';
import '../../domain/repositories/device_repository.dart';
import '../sdk/sdk_locator.dart';

/// [DeviceRepository] backed by the `adb` command-line tool.
@LazySingleton(as: DeviceRepository)
class DeviceRepositoryImpl implements DeviceRepository {
  DeviceRepositoryImpl(this._runner, this._locator);

  final CommandRunner _runner;
  final SdkLocator _locator;

  static const _timeout = Duration(seconds: 20);

  String get _adb {
    final path = _locator.adb;
    if (path == null) {
      throw const ExecutableNotFoundFailure(
        'adb',
        suggestion: 'Install "platform-tools" from the SDK Manager.',
      );
    }
    return path;
  }

  // ---- Listing -------------------------------------------------------------

  @override
  Future<List<Device>> listDevices() async {
    final result = await _runner.run(_adb, ['devices', '-l'], timeout: _timeout);
    final devices = parseDevices(result.stdout);

    // Enrich online devices with properties + battery, concurrently.
    return Future.wait(devices.map((d) async {
      if (!d.state.isOnline) return d;
      final enriched = await _enrich(d);
      return enriched;
    }));
  }

  /// Parses `adb devices -l` output. Static & pure for unit testing.
  static List<Device> parseDevices(String output) {
    final devices = <Device>[];
    for (final rawLine in const LineSplitter().convert(output)) {
      final line = rawLine.trim();
      if (line.isEmpty ||
          line.startsWith('List of devices') ||
          line.startsWith('*')) {
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final serial = parts[0];
      final state = _parseState(parts[1]);

      String? valueOf(String key) {
        for (final token in parts.skip(2)) {
          if (token.startsWith('$key:')) return token.substring(key.length + 1);
        }
        return null;
      }

      devices.add(Device(
        serial: serial,
        state: state,
        model: valueOf('model'),
        product: valueOf('product'),
        transportId: valueOf('transport_id'),
      ));
    }
    return devices;
  }

  static DeviceState _parseState(String raw) => switch (raw) {
        'device' => DeviceState.device,
        'offline' => DeviceState.offline,
        'unauthorized' => DeviceState.unauthorized,
        'no' || 'no permissions' => DeviceState.noPermissions,
        'bootloader' => DeviceState.bootloader,
        _ => DeviceState.unknown,
      };

  Future<Device> _enrich(Device device) async {
    try {
      final results = await Future.wait([
        _runner.run(_adb, ['-s', device.serial, 'shell', 'getprop'],
            timeout: _timeout),
        _runner.run(
            _adb, ['-s', device.serial, 'shell', 'dumpsys', 'battery'],
            timeout: _timeout),
      ]);
      final props = _parseGetprop(results[0].stdout);
      final battery = _parseBattery(results[1].stdout);
      return device.copyWith(
        manufacturer: props['ro.product.manufacturer'],
        androidRelease: props['ro.build.version.release'],
        sdkInt: int.tryParse(props['ro.build.version.sdk'] ?? ''),
        batteryLevel: battery,
      );
    } on Failure {
      return device; // enrichment is best-effort
    }
  }

  static Map<String, String> _parseGetprop(String output) {
    final map = <String, String>{};
    final pattern = RegExp(r'\[(.+?)\]:\s*\[(.*?)\]');
    for (final match in pattern.allMatches(output)) {
      map[match.group(1)!] = match.group(2)!;
    }
    return map;
  }

  static int? _parseBattery(String output) {
    final match = RegExp(r'level:\s*(\d+)').firstMatch(output);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  // ---- Actions -------------------------------------------------------------

  @override
  Future<void> reboot(String serial, RebootTarget target) async {
    final args = ['-s', serial, 'reboot', if (target != RebootTarget.system) target.name];
    final result = await _runner.run(_adb, args, timeout: _timeout);
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Failed to reboot "$serial".',
        exitCode: result.exitCode,
        output: result.combinedOutput,
      );
    }
  }

  @override
  Future<RunningCommand> installApk(String serial, String apkPath) {
    if (!File(apkPath).existsSync()) {
      throw FileSystemFailure('APK not found: $apkPath');
    }
    return _runner.start(_adb, ['-s', serial, 'install', '-r', apkPath]);
  }

  @override
  Future<String> screenshot(String serial) async {
    const remote = '/sdcard/_asm_screenshot.png';
    // Capture on-device, then pull to the host to avoid piping binary data
    // through the (text-decoded) command runner.
    final cap = await _runner.run(
      _adb,
      ['-s', serial, 'shell', 'screencap', '-p', remote],
      timeout: _timeout,
    );
    if (!cap.isSuccess) {
      throw ProcessFailure('Screen capture failed.',
          exitCode: cap.exitCode, output: cap.combinedOutput);
    }

    final dir = await _screenshotDir();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final local = p.join(dir, 'screenshot_${serial}_$stamp.png');

    final pull = await _runner.run(_adb, ['-s', serial, 'pull', remote, local],
        timeout: _timeout);
    // Best-effort cleanup of the temp file on the device.
    await _runner.run(_adb, ['-s', serial, 'shell', 'rm', remote],
        timeout: _timeout);

    if (!pull.isSuccess || !File(local).existsSync()) {
      throw ProcessFailure('Failed to save screenshot.',
          exitCode: pull.exitCode, output: pull.combinedOutput);
    }
    return local;
  }

  Future<String> _screenshotDir() async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    dir ??= await getApplicationDocumentsDirectory();
    final shots = Directory(p.join(dir.path, 'AndroidSdkManager', 'screenshots'));
    if (!shots.existsSync()) shots.createSync(recursive: true);
    return shots.path;
  }

  @override
  Future<void> disconnect(Device device) async {
    if (device.isEmulator) {
      await _runner.run(_adb, ['-s', device.serial, 'emu', 'kill'],
          timeout: _timeout);
    } else if (device.isNetwork) {
      await _runner.run(_adb, ['disconnect', device.serial], timeout: _timeout);
    } else {
      throw const UnknownFailure(
        'USB devices cannot be disconnected from software; unplug the cable.',
      );
    }
  }

  @override
  Future<void> openShell(String serial) =>
      _openConsole([_adb, '-s', serial, 'shell']);

  @override
  Future<void> openLogcat(String serial) =>
      _openConsole([_adb, '-s', serial, 'logcat']);

  @override
  Future<RunningCommand> streamLogcat(String serial) async {
    // Clear the ring buffer first so the view starts fresh, then stream in the
    // simple `brief` format we parse for priority/tag.
    await _runner.run(_adb, ['-s', serial, 'logcat', '-c'],
        timeout: const Duration(seconds: 10));
    return _runner.start(_adb, ['-s', serial, 'logcat', '-v', 'brief']);
  }

  /// Opens a detached external console running [command].
  Future<void> _openConsole(List<String> command) async {
    if (Platform.isWindows) {
      // `start "" cmd /k <command>` spawns a persistent console window.
      await Process.start(
        'cmd',
        ['/c', 'start', '', 'cmd', '/k', command.join(' ')],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
    } else {
      await Process.start(command.first, command.sublist(1),
          mode: ProcessStartMode.detached);
    }
  }
}
