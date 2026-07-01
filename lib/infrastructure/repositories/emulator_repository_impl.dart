import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/avd.dart';
import '../../domain/entities/avd_create_request.dart';
import '../../domain/entities/device_definition.dart';
import '../../domain/entities/system_image.dart';
import '../../domain/repositories/emulator_repository.dart';
import '../sdk/sdk_locator.dart';

/// [EmulatorRepository] backed by the real `avdmanager`, `emulator` and `adb`
/// command-line tools plus direct manipulation of the AVD directory.
@LazySingleton(as: EmulatorRepository)
class EmulatorRepositoryImpl implements EmulatorRepository {
  EmulatorRepositoryImpl(this._runner, this._locator);

  final CommandRunner _runner;
  final SdkLocator _locator;

  static final Logger _log = Logger('EmulatorRepository');
  static const _timeout = Duration(seconds: 60);

  // ---- Tool path guards ----------------------------------------------------

  String get _avdManager {
    final path = _locator.avdManager;
    if (path == null) {
      throw const ExecutableNotFoundFailure(
        'avdmanager',
        suggestion: 'Install "cmdline-tools;latest" from the SDK Manager.',
      );
    }
    return path;
  }

  String get _emulator {
    final path = _locator.emulator;
    if (path == null) {
      throw const ExecutableNotFoundFailure(
        'emulator',
        suggestion: 'Install the "emulator" package from the SDK Manager.',
      );
    }
    return path;
  }

  String? get _adb => _locator.adb;

  /// Directory that holds `<name>.avd` folders and `<name>.ini` files.
  String get _avdHome {
    final env = Platform.environment;
    final explicit = env['ANDROID_AVD_HOME'];
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final sdkHome = env['ANDROID_SDK_HOME'] ?? env['USERPROFILE'] ?? env['HOME'];
    return p.join(sdkHome ?? '.', '.android', 'avd');
  }

  // ---- Listing -------------------------------------------------------------

  @override
  Future<List<Avd>> listAvds() async {
    final result = await _runner.run(
      _avdManager,
      ['list', 'avd'],
      timeout: _timeout,
    );
    final avds = _parseAvdList(result.stdout);

    // Annotate with running state (best-effort; never fails the listing).
    final running = await _runningAvdNames();
    return avds
        .map((a) => running.contains(a.name) ? a.copyWith(isRunning: true) : a)
        .toList();
  }

  /// Parses the block-structured output of `avdmanager list avd`.
  List<Avd> _parseAvdList(String output) {
    final avds = <Avd>[];
    // Entries are separated by a line of dashes; drop the header preamble.
    final body = output.contains(':')
        ? output.substring(output.indexOf('\n') + 1)
        : output;
    for (final block in body.split(RegExp(r'-{4,}'))) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;
      final map = <String, String>{};
      String? tag, abi;
      for (final rawLine in const LineSplitter().convert(trimmed)) {
        final line = rawLine.trim();
        final tagAbi = RegExp(r'Tag/ABI:\s*([^/]+)/(\S+)').firstMatch(line);
        if (tagAbi != null) {
          tag = tagAbi.group(1)?.trim();
          abi = tagAbi.group(2)?.trim();
        }
        final based = RegExp(r'Based on:\s*Android\s+([\d.]+)').firstMatch(line);
        if (based != null) map['AndroidVersion'] = based.group(1)!;
        final idx = line.indexOf(':');
        if (idx > 0) {
          final key = line.substring(0, idx).trim();
          final value = line.substring(idx + 1).trim();
          if (key.isNotEmpty && value.isNotEmpty) map.putIfAbsent(key, () => value);
        }
      }
      final name = map['Name'];
      if (name == null) continue;

      final deviceRaw = map['Device']; // "pixel_6 (Pixel 6)"
      String? deviceId, deviceName;
      if (deviceRaw != null) {
        final m = RegExp(r'([^\s(]+)\s*(?:\((.*)\))?').firstMatch(deviceRaw);
        deviceId = m?.group(1);
        deviceName = m?.group(2) ?? deviceRaw;
      }

      avds.add(Avd(
        name: name,
        deviceId: deviceId,
        deviceName: deviceName,
        target: map['Target'],
        androidVersion: map['AndroidVersion'],
        apiLevel: _apiFromPath(map['Path']) ?? _apiFromTarget(map['Target']),
        tag: tag,
        abi: abi,
        path: map['Path'],
        sdcard: map['Sdcard'],
        error: map['Error'],
      ));
    }
    return avds;
  }

  int? _apiFromPath(String? path) {
    if (path == null) return null;
    final m = RegExp(r'android-(\d+)').firstMatch(path);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  int? _apiFromTarget(String? target) {
    if (target == null) return null;
    final m = RegExp(r'API\s+(\d+)').firstMatch(target);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  @override
  Future<List<SystemImage>> listSystemImages() async {
    final root = _locator.sdkRoot;
    if (root == null) return const [];
    final base = Directory(p.join(root, 'system-images'));
    if (!base.existsSync()) return const [];

    final images = <SystemImage>[];
    // Layout: system-images/<platform>/<tag>/<abi>/
    for (final platformDir in base.listSync().whereType<Directory>()) {
      final platform = p.basename(platformDir.path); // android-34
      final api =
          int.tryParse(RegExp(r'(\d+)').firstMatch(platform)?.group(1) ?? '');
      if (api == null) continue;
      for (final tagDir in platformDir.listSync().whereType<Directory>()) {
        final tag = p.basename(tagDir.path);
        for (final abiDir in tagDir.listSync().whereType<Directory>()) {
          final abi = p.basename(abiDir.path);
          // A valid image directory contains a system.img or similar.
          final hasImage = abiDir
              .listSync()
              .whereType<File>()
              .any((f) => p.basename(f.path).endsWith('.img') ||
                  p.basename(f.path) == 'source.properties');
          if (!hasImage) continue;
          images.add(SystemImage(
            packagePath: 'system-images;$platform;$tag;$abi',
            platform: platform,
            apiLevel: api,
            tag: tag,
            abi: abi,
          ));
        }
      }
    }
    images.sort((a, b) {
      final byApi = b.apiLevel.compareTo(a.apiLevel);
      return byApi != 0 ? byApi : a.tag.compareTo(b.tag);
    });
    return images;
  }

  @override
  Future<List<DeviceDefinition>> listDeviceDefinitions() async {
    final result = await _runner.run(
      _avdManager,
      ['list', 'device'],
      timeout: _timeout,
    );
    return _parseDeviceList(result.stdout);
  }

  List<DeviceDefinition> _parseDeviceList(String output) {
    final devices = <DeviceDefinition>[];
    for (final block in output.split(RegExp(r'-{4,}'))) {
      final trimmed = block.trim();
      if (trimmed.isEmpty || !trimmed.contains('id:')) continue;
      String? id, name, oem;
      for (final rawLine in const LineSplitter().convert(trimmed)) {
        final line = rawLine.trim();
        final idM = RegExp(r'id:\s*\d+\s*or\s*"([^"]+)"').firstMatch(line) ??
            RegExp(r'id:\s*(\S+)').firstMatch(line);
        if (idM != null) id = idM.group(1);
        if (line.startsWith('Name:')) name = line.substring(5).trim();
        if (line.startsWith('OEM')) {
          final i = line.indexOf(':');
          if (i > 0) oem = line.substring(i + 1).trim();
        }
      }
      if (id != null) {
        devices.add(DeviceDefinition(id: id, name: name ?? id, oem: oem));
      }
    }
    return devices;
  }

  // ---- Create --------------------------------------------------------------

  @override
  Future<void> createAvd(AvdCreateRequest request) async {
    final name = request.sanitizedName;
    if (name.isEmpty) {
      throw const UnknownFailure('AVD name must not be empty.');
    }

    final args = <String>[
      'create', 'avd',
      '-n', name,
      '-k', request.systemImage.packagePath,
      '-d', request.deviceId,
      if (request.sdCardMb > 0) ...['-c', '${request.sdCardMb}M'],
      '--force',
    ];

    // avdmanager prompts to create a custom hardware profile; answer "no".
    final command = await _runner.start(_avdManager, args);
    command.writeLine('no');
    final result = await command.result.timeout(_timeout, onTimeout: () {
      command.cancel();
      throw const TimeoutFailure('Creating the AVD took too long.');
    });

    if (!result.isSuccess) {
      throw ProcessFailure(
        'avdmanager failed to create the AVD.',
        exitCode: result.exitCode,
        output: result.combinedOutput,
        suggestion: 'Check that the selected system image is installed.',
      );
    }

    await _applyConfig(name, request);
  }

  /// Writes the hardware settings from [request] into the AVD's `config.ini`.
  Future<void> _applyConfig(String name, AvdCreateRequest request) async {
    final configFile = File(p.join(_avdHome, '$name.avd', 'config.ini'));
    if (!configFile.existsSync()) return; // nothing to tune

    final props = <String, String>{
      'hw.ramSize': '${request.ramMb}',
      'vm.heapSize': '${request.vmHeapMb}',
      'disk.dataPartition.size': '${request.internalStorageMb}M',
      'hw.gpu.enabled': request.gpuMode == GpuMode.off ? 'no' : 'yes',
      'hw.gpu.mode': request.gpuMode.iniValue,
      'hw.camera.back': request.enableCamera ? 'virtualscene' : 'none',
      'hw.camera.front': request.enableCamera ? 'emulated' : 'none',
      'hw.cpu.ncore': '${request.cpuCores}',
      if (request.sdCardMb > 0) 'sdcard.size': '${request.sdCardMb}M',
    };

    final lines = configFile.readAsLinesSync();
    final seen = <String>{};
    final out = <String>[];
    for (final line in lines) {
      final eq = line.indexOf('=');
      if (eq <= 0) {
        out.add(line);
        continue;
      }
      final key = line.substring(0, eq).trim();
      if (props.containsKey(key)) {
        out.add('$key=${props[key]}');
        seen.add(key);
      } else {
        out.add(line);
      }
    }
    for (final entry in props.entries) {
      if (!seen.contains(entry.key)) out.add('${entry.key}=${entry.value}');
    }
    configFile.writeAsStringSync('${out.join('\n')}\n');
  }

  // ---- Mutations -----------------------------------------------------------

  @override
  Future<void> deleteAvd(String name) async {
    final result = await _runner.run(
      _avdManager,
      ['delete', 'avd', '-n', name],
      timeout: _timeout,
    );
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Failed to delete "$name".',
        exitCode: result.exitCode,
        output: result.combinedOutput,
      );
    }
  }

  @override
  Future<void> wipeData(String name) async {
    // Immediate wipe: remove the mutable user-data and snapshots. The pristine
    // userdata.img is left untouched so the next boot regenerates cleanly.
    final avdDir = Directory(p.join(_avdHome, '$name.avd'));
    if (!avdDir.existsSync()) {
      throw FileSystemFailure('AVD directory for "$name" was not found.');
    }
    for (final entity in avdDir.listSync()) {
      final base = p.basename(entity.path);
      if (entity is File && base.startsWith('userdata-qemu.img')) {
        entity.deleteSync();
      } else if (entity is Directory && base == 'snapshots') {
        entity.deleteSync(recursive: true);
      }
    }
  }

  @override
  Future<void> duplicateAvd(String source, String newName) async {
    final target = newName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final srcDir = Directory(p.join(_avdHome, '$source.avd'));
    final srcIni = File(p.join(_avdHome, '$source.ini'));
    if (!srcDir.existsSync() || !srcIni.existsSync()) {
      throw FileSystemFailure('Source AVD "$source" was not found.');
    }
    final dstDir = Directory(p.join(_avdHome, '$target.avd'));
    if (dstDir.existsSync()) {
      throw FileSystemFailure('An AVD named "$target" already exists.');
    }

    // Copy the .avd directory contents. Skip runtime lock files and tolerate
    // any file that is currently locked (e.g. when the source AVD is running),
    // so duplicating a running emulator still succeeds with a clean copy.
    dstDir.createSync(recursive: true);
    for (final entity in srcDir.listSync(recursive: true)) {
      final rel = p.relative(entity.path, from: srcDir.path);
      final base = p.basename(entity.path);
      if (base.endsWith('.lock')) continue; // *.lock, multiinstance.lock, …
      final destPath = p.join(dstDir.path, rel);
      if (entity is Directory) {
        Directory(destPath).createSync(recursive: true);
      } else if (entity is File) {
        Directory(p.dirname(destPath)).createSync(recursive: true);
        try {
          entity.copySync(destPath);
        } on FileSystemException catch (e) {
          _log.warning('duplicate: skipping locked file $rel (${e.osError})');
        }
      }
    }

    // Rewrite the top-level <name>.ini to point at the new directory.
    final iniContent = srcIni
        .readAsStringSync()
        .replaceAll('$source.avd', '$target.avd');
    File(p.join(_avdHome, '$target.ini')).writeAsStringSync(iniContent);

    // Update AvdId / display name inside config.ini.
    final config = File(p.join(dstDir.path, 'config.ini'));
    if (config.existsSync()) {
      final updated = config
          .readAsLinesSync()
          .map((line) {
            if (line.startsWith('AvdId=')) return 'AvdId=$target';
            if (line.startsWith('avd.ini.displayname=')) {
              return 'avd.ini.displayname=$target';
            }
            return line;
          })
          .join('\n');
      config.writeAsStringSync('$updated\n');
    }
  }

  // ---- Launch / stop -------------------------------------------------------

  @override
  Future<RunningCommand> launch(String name, LaunchOptions options) {
    return _runner.start(_emulator, options.toArgs(name));
  }

  @override
  Future<void> stop(String name) async {
    final adb = _adb;
    if (adb == null) return;
    final serial = await _serialForAvd(name);
    if (serial == null) return;
    await _runner.run(adb, ['-s', serial, 'emu', 'kill'],
        timeout: const Duration(seconds: 10));
  }

  // ---- adb helpers ---------------------------------------------------------

  /// Set of AVD names that currently have a running emulator process.
  Future<Set<String>> _runningAvdNames() async {
    final adb = _adb;
    if (adb == null) return {};
    final names = <String>{};
    try {
      for (final serial in await _emulatorSerials()) {
        final name = await _avdNameForSerial(serial);
        if (name != null) names.add(name);
      }
    } on Failure {
      // adb unavailable — treat everything as stopped.
    }
    return names;
  }

  Future<List<String>> _emulatorSerials() async {
    final adb = _adb;
    if (adb == null) return const [];
    final result = await _runner.run(adb, ['devices'],
        timeout: const Duration(seconds: 10));
    return const LineSplitter()
        .convert(result.stdout)
        .map((l) => l.trim())
        .where((l) => l.startsWith('emulator-') && l.contains('device'))
        .map((l) => l.split(RegExp(r'\s+')).first)
        .toList();
  }

  Future<String?> _avdNameForSerial(String serial) async {
    final adb = _adb;
    if (adb == null) return null;
    final result = await _runner.run(
      adb,
      ['-s', serial, 'emu', 'avd', 'name'],
      timeout: const Duration(seconds: 10),
    );
    // Output: "<AvdName>\nOK". Take the first non-empty, non-OK line.
    final name = const LineSplitter()
        .convert(result.stdout)
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && l != 'OK', orElse: () => '');
    return name.isEmpty ? null : name;
  }

  Future<String?> _serialForAvd(String name) async {
    for (final serial in await _emulatorSerials()) {
      if (await _avdNameForSerial(serial) == name) return serial;
    }
    return null;
  }
}
