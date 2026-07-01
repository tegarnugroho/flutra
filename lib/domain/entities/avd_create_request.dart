import 'system_image.dart';

/// GPU emulation mode for `hw.gpu.mode`.
enum GpuMode { auto, host, swiftshaderIndirect, angleIndirect, guest, off }

extension GpuModeValue on GpuMode {
  String get iniValue => switch (this) {
        GpuMode.auto => 'auto',
        GpuMode.host => 'host',
        GpuMode.swiftshaderIndirect => 'swiftshader_indirect',
        GpuMode.angleIndirect => 'angle_indirect',
        GpuMode.guest => 'guest',
        GpuMode.off => 'off',
      };

  String get label => switch (this) {
        GpuMode.auto => 'Automatic',
        GpuMode.host => 'Hardware (host GPU)',
        GpuMode.swiftshaderIndirect => 'Software (SwiftShader)',
        GpuMode.angleIndirect => 'ANGLE (D3D)',
        GpuMode.guest => 'Guest',
        GpuMode.off => 'Off',
      };
}

/// All parameters needed to create and configure a new AVD.
class AvdCreateRequest {
  const AvdCreateRequest({
    required this.name,
    required this.systemImage,
    required this.deviceId,
    this.ramMb = 2048,
    this.vmHeapMb = 256,
    this.internalStorageMb = 6144,
    this.sdCardMb = 512,
    this.gpuMode = GpuMode.auto,
    this.enableCamera = true,
    this.cpuCores = 4,
  });

  final String name;
  final SystemImage systemImage;
  final String deviceId;
  final int ramMb;
  final int vmHeapMb;
  final int internalStorageMb;
  final int sdCardMb;
  final GpuMode gpuMode;
  final bool enableCamera;
  final int cpuCores;

  /// The AVD name sanitised to the characters avdmanager accepts.
  String get sanitizedName =>
      name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}

/// Runtime flags for launching an emulator.
class LaunchOptions {
  const LaunchOptions({
    this.coldBoot = false,
    this.noSnapshot = false,
    this.wipeData = false,
    this.readOnly = false,
    this.verbose = false,
    this.noWindow = false,
    this.gpuMode,
    this.memoryMb,
    this.extraArgs = const [],
  });

  final bool coldBoot;
  final bool noSnapshot;
  final bool wipeData;
  final bool readOnly;
  final bool verbose;
  final bool noWindow;
  final GpuMode? gpuMode;
  final int? memoryMb;
  final List<String> extraArgs;

  /// Builds the emulator argument list for AVD [name].
  List<String> toArgs(String name) => [
        '-avd', name,
        if (coldBoot) '-no-snapshot-load',
        if (noSnapshot) '-no-snapshot',
        if (wipeData) '-wipe-data',
        if (readOnly) '-read-only',
        if (verbose) '-verbose',
        if (noWindow) '-no-window',
        if (gpuMode != null) ...['-gpu', gpuMode!.iniValue],
        if (memoryMb != null) ...['-memory', '$memoryMb'],
        ...extraArgs,
      ];
}
