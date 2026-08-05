part of 'create_emulator_cubit.dart';

enum LoadStatus { initial, loading, ready, failure }

/// The wizard steps, in order.
enum WizardStep { device, apiLevel, image, abi, configure }

extension WizardStepInfo on WizardStep {
  String get title => switch (this) {
    WizardStep.device => 'Choose device',
    WizardStep.apiLevel => 'Android version',
    WizardStep.image => 'System image',
    WizardStep.abi => 'ABI',
    WizardStep.configure => 'Configuration',
  };

  /// Short form for the stepper, where five labels share one row.
  String get shortTitle => switch (this) {
    WizardStep.device => 'Device',
    WizardStep.apiLevel => 'Android',
    WizardStep.image => 'Image',
    WizardStep.abi => 'ABI',
    WizardStep.configure => 'Config',
  };
}

/// Which half of the device step is showing.
///
/// Both halves are step 1: the user picks a form factor first, then a profile
/// inside it. Modelled as state rather than a route so wizard Back, the
/// stepper and the footer all stay in one place.
enum DeviceStepPhase { categories, devices }

/// Hardware configuration collected on the final wizard step.
class EmulatorConfig extends Equatable {
  const EmulatorConfig({
    this.ramMb = 2048,
    this.vmHeapMb = 256,
    this.internalStorageMb = 6144,
    this.sdCardMb = 512,
    this.gpuMode = GpuMode.auto,
    this.enableCamera = true,
    this.cpuCores = 4,
  });

  final int ramMb;
  final int vmHeapMb;
  final int internalStorageMb;
  final int sdCardMb;
  final GpuMode gpuMode;
  final bool enableCamera;
  final int cpuCores;

  EmulatorConfig copyWith({
    int? ramMb,
    int? vmHeapMb,
    int? internalStorageMb,
    int? sdCardMb,
    GpuMode? gpuMode,
    bool? enableCamera,
    int? cpuCores,
  }) {
    return EmulatorConfig(
      ramMb: ramMb ?? this.ramMb,
      vmHeapMb: vmHeapMb ?? this.vmHeapMb,
      internalStorageMb: internalStorageMb ?? this.internalStorageMb,
      sdCardMb: sdCardMb ?? this.sdCardMb,
      gpuMode: gpuMode ?? this.gpuMode,
      enableCamera: enableCamera ?? this.enableCamera,
      cpuCores: cpuCores ?? this.cpuCores,
    );
  }

  @override
  List<Object?> get props =>
      [ramMb, vmHeapMb, internalStorageMb, sdCardMb, gpuMode, enableCamera, cpuCores];
}

/// Immutable state for the Create Emulator wizard.
class CreateEmulatorState extends Equatable {
  const CreateEmulatorState({
    this.loadStatus = LoadStatus.initial,
    this.step = WizardStep.device,
    this.devicePhase = DeviceStepPhase.categories,
    this.browsingCategory,
    this.deviceQuery = '',
    this.images = const [],
    this.devices = const [],
    this.deviceId,
    this.apiLevel,
    this.tag,
    this.abi,
    this.name = '',
    this.nameEdited = false,
    this.config = const EmulatorConfig(),
    this.submitting = false,
    this.createdName,
    this.errorMessage,
  });

  final LoadStatus loadStatus;
  final WizardStep step;

  /// Which half of [WizardStep.device] is showing.
  final DeviceStepPhase devicePhase;

  /// The category whose profiles are listed in [DeviceStepPhase.devices].
  final DeviceCategory? browsingCategory;

  /// Search text, scoped to [browsingCategory].
  final String deviceQuery;

  final List<SystemImage> images;
  final List<DeviceDefinition> devices;

  final String? deviceId;
  final int? apiLevel;
  final String? tag;
  final String? abi;
  final String name;
  final bool nameEdited;
  final EmulatorConfig config;

  final bool submitting;

  /// Set once the AVD is created successfully.
  final String? createdName;
  final String? errorMessage;

  bool get isReady => loadStatus == LoadStatus.ready;
  bool get isSuccess => createdName != null;

  /// Distinct API levels among the installed system images, newest first.
  List<int> get availableApiLevels {
    final set = images.map((i) => i.apiLevel).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return set;
  }

  /// Distinct tags available for the currently-selected API level.
  List<String> get tagsForApi {
    if (apiLevel == null) return const [];
    return images
        .where((i) => i.apiLevel == apiLevel)
        .map((i) => i.tag)
        .toSet()
        .toList()
      ..sort();
  }

  /// ABIs available for the selected API level + tag.
  List<String> get abisForSelection {
    if (apiLevel == null || tag == null) return const [];
    return images
        .where((i) => i.apiLevel == apiLevel && i.tag == tag)
        .map((i) => i.abi)
        .toSet()
        .toList()
      ..sort();
  }

  /// The concrete image matching the full selection, if any.
  SystemImage? get selectedImage {
    if (apiLevel == null || tag == null || abi == null) return null;
    for (final image in images) {
      if (image.apiLevel == apiLevel && image.tag == tag && image.abi == abi) {
        return image;
      }
    }
    return null;
  }

  /// How many profiles each category holds. Categories with none are absent,
  /// so the picker can render exactly what the catalog offers.
  Map<DeviceCategory, int> get deviceCategoryCounts {
    final counts = <DeviceCategory, int>{};
    for (final device in devices) {
      counts.update(device.category, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  /// Non-empty categories, in the enum's declaration order.
  List<DeviceCategory> get deviceCategories {
    final counts = deviceCategoryCounts;
    return DeviceCategory.values.where(counts.containsKey).toList();
  }

  /// Profiles of [browsingCategory], narrowed by [deviceQuery].
  List<DeviceDefinition> get browsedDevices {
    if (browsingCategory == null) return const [];
    final query = deviceQuery.trim().toLowerCase();
    return devices.where((d) {
      if (d.category != browsingCategory) return false;
      if (query.isEmpty) return true;
      return d.name.toLowerCase().contains(query) ||
          (d.oem?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  DeviceDefinition? get selectedDevice {
    for (final d in devices) {
      if (d.id == deviceId) return d;
    }
    return null;
  }

  /// Whether the current step has a valid selection so the user can proceed.
  bool get canAdvance => switch (step) {
        // A category alone is not a selection, so the category phase can
        // never advance even when a device is already picked.
        WizardStep.device =>
          devicePhase == DeviceStepPhase.devices && deviceId != null,
        WizardStep.apiLevel => apiLevel != null,
        WizardStep.image => tag != null,
        WizardStep.abi => abi != null,
        WizardStep.configure => selectedImage != null && name.trim().isNotEmpty,
      };

  CreateEmulatorState copyWith({
    LoadStatus? loadStatus,
    WizardStep? step,
    DeviceStepPhase? devicePhase,
    DeviceCategory? browsingCategory,
    String? deviceQuery,
    List<SystemImage>? images,
    List<DeviceDefinition>? devices,
    String? deviceId,
    int? apiLevel,
    String? tag,
    String? abi,
    String? name,
    bool? nameEdited,
    EmulatorConfig? config,
    bool? submitting,
    String? createdName,
    String? errorMessage,
    bool clearError = false,
    bool clearTag = false,
    bool clearAbi = false,
  }) {
    return CreateEmulatorState(
      loadStatus: loadStatus ?? this.loadStatus,
      step: step ?? this.step,
      devicePhase: devicePhase ?? this.devicePhase,
      browsingCategory: browsingCategory ?? this.browsingCategory,
      deviceQuery: deviceQuery ?? this.deviceQuery,
      images: images ?? this.images,
      devices: devices ?? this.devices,
      deviceId: deviceId ?? this.deviceId,
      apiLevel: apiLevel ?? this.apiLevel,
      tag: clearTag ? null : (tag ?? this.tag),
      abi: clearAbi ? null : (abi ?? this.abi),
      name: name ?? this.name,
      nameEdited: nameEdited ?? this.nameEdited,
      config: config ?? this.config,
      submitting: submitting ?? this.submitting,
      createdName: createdName ?? this.createdName,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        loadStatus,
        step,
        devicePhase,
        browsingCategory,
        deviceQuery,
        images,
        devices,
        deviceId,
        apiLevel,
        tag,
        abi,
        name,
        nameEdited,
        config,
        submitting,
        createdName,
        errorMessage,
      ];
}
