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

/// How far along the deferred install + create pipeline the wizard is.
enum InstallPhase {
  idle,
  downloading,
  installing,
  verifying,
  creating,
}

extension InstallPhaseLabel on InstallPhase {
  String get label => switch (this) {
    InstallPhase.idle => '',
    InstallPhase.downloading => 'Downloading system image…',
    InstallPhase.installing => 'Installing system image…',
    InstallPhase.verifying => 'Verifying install…',
    InstallPhase.creating => 'Creating AVD…',
  };
}

/// One `system-images;…` package the wizard can build an AVD on, whether or not
/// it is on disk yet.
///
/// The catalogue comes from `sdkmanager --list`, so "available" entries are
/// selectable and downloaded during the final step.
class ImageOption extends Equatable {
  const ImageOption({
    required this.packagePath,
    required this.apiLevel,
    required this.tag,
    required this.abi,
    required this.installed,
  });

  /// Parses a `system-images;android-34;google_apis;x86_64` path.
  ///
  /// Returns null for anything that isn't a four-part system-image path with a
  /// numeric API level — `android-TiramisuPrivacySandbox` and friends.
  static ImageOption? tryParse(String path, {required bool installed}) {
    final parts = path.split(';');
    if (parts.length != 4 || parts.first != 'system-images') return null;
    final api = int.tryParse(parts[1].replaceFirst('android-', ''));
    if (api == null) return null;
    return ImageOption(
      packagePath: path,
      apiLevel: api,
      tag: parts[2],
      abi: parts[3],
      installed: installed,
    );
  }

  final String packagePath;
  final int apiLevel;
  final String tag;
  final String abi;
  final bool installed;

  SystemImage toSystemImage() => SystemImage(
    packagePath: packagePath,
    platform: 'android-$apiLevel',
    apiLevel: apiLevel,
    tag: tag,
    abi: abi,
  );

  ImageOption copyWith({bool? installed}) => ImageOption(
    packagePath: packagePath,
    apiLevel: apiLevel,
    tag: tag,
    abi: abi,
    installed: installed ?? this.installed,
  );

  @override
  List<Object?> get props => [packagePath, installed];
}

/// Marketing name and codename for an API level.
///
/// Only the levels the emulator still ships images for are named; anything
/// older falls back to the bare level, which is what sdkmanager shows anyway.
({String version, String? codename}) androidVersionOf(int api) => switch (api) {
  36 => (version: 'Android 16', codename: 'Baklava'),
  35 => (version: 'Android 15', codename: 'VanillaIceCream'),
  34 => (version: 'Android 14', codename: 'UpsideDownCake'),
  33 => (version: 'Android 13', codename: 'Tiramisu'),
  32 => (version: 'Android 12L', codename: 'Sv2'),
  31 => (version: 'Android 12', codename: 'S'),
  30 => (version: 'Android 11', codename: 'R'),
  29 => (version: 'Android 10', codename: 'Q'),
  28 => (version: 'Android 9', codename: 'Pie'),
  27 || 26 => (version: 'Android 8', codename: 'Oreo'),
  25 || 24 => (version: 'Android 7', codename: 'Nougat'),
  23 => (version: 'Android 6', codename: 'Marshmallow'),
  _ => (version: 'API $api', codename: null),
};

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
    this.options = const [],
    this.devices = const [],
    this.showOlderApis = false,
    this.installPhase = InstallPhase.idle,
    this.installProgress,
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

  /// Every system-image package sdkmanager knows about, installed or not.
  final List<ImageOption> options;

  final List<DeviceDefinition> devices;

  /// Whether the API list is showing everything or just the recent levels.
  final bool showOlderApis;

  /// Where the final Create step is in the install + create pipeline.
  final InstallPhase installPhase;

  /// 0..1 while sdkmanager reports a percentage; null when indeterminate.
  final double? installProgress;

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

  /// How many API levels the list shows before the "older versions" expander.
  static const int recentApiCount = 6;

  /// Distinct API levels with at least one system image, newest first.
  List<int> get availableApiLevels {
    final set = options.map((o) => o.apiLevel).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return set;
  }

  /// The levels shown by default — the newest few.
  List<int> get recentApiLevels =>
      availableApiLevels.take(recentApiCount).toList();

  /// Everything behind the "Show older versions" expander.
  List<int> get olderApiLevels =>
      availableApiLevels.skip(recentApiCount).toList();

  /// The levels currently on screen.
  List<int> get visibleApiLevels =>
      showOlderApis ? availableApiLevels : recentApiLevels;

  /// True when any image for [api] is already on disk.
  bool isApiInstalled(int api) =>
      options.any((o) => o.apiLevel == api && o.installed);

  /// Distinct tags available for the currently-selected API level.
  List<String> get tagsForApi {
    if (apiLevel == null) return const [];
    return options
        .where((o) => o.apiLevel == apiLevel)
        .map((o) => o.tag)
        .toSet()
        .toList()
      ..sort();
  }

  /// True when any ABI of [tag] is installed for the selected API. The exact
  /// package is only pinned down once an ABI is chosen.
  bool isTagInstalled(String tag) => options.any(
    (o) => o.apiLevel == apiLevel && o.tag == tag && o.installed,
  );

  /// ABIs available for the selected API level + tag.
  List<String> get abisForSelection {
    if (apiLevel == null || tag == null) return const [];
    return options
        .where((o) => o.apiLevel == apiLevel && o.tag == tag)
        .map((o) => o.abi)
        .toSet()
        .toList()
      ..sort();
  }

  /// The catalogue entry for [abi] under the current API + tag.
  ImageOption? optionForAbi(String abi) {
    for (final o in options) {
      if (o.apiLevel == apiLevel && o.tag == tag && o.abi == abi) return o;
    }
    return null;
  }

  /// The entry matching the full selection, if any.
  ImageOption? get selectedOption => abi == null ? null : optionForAbi(abi!);

  /// The concrete image matching the full selection, if any.
  SystemImage? get selectedImage => selectedOption?.toSystemImage();

  /// True when Create has to fetch the chosen package first.
  bool get needsDownload => selectedOption?.installed == false;

  /// True while the Create step is downloading, installing or creating.
  bool get isWorking => installPhase != InstallPhase.idle;

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
    List<ImageOption>? options,
    List<DeviceDefinition>? devices,
    bool? showOlderApis,
    InstallPhase? installPhase,
    double? installProgress,
    bool clearProgress = false,
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
      options: options ?? this.options,
      devices: devices ?? this.devices,
      showOlderApis: showOlderApis ?? this.showOlderApis,
      installPhase: installPhase ?? this.installPhase,
      installProgress: clearProgress
          ? null
          : (installProgress ?? this.installProgress),
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
        options,
        devices,
        showOlderApis,
        installPhase,
        installProgress,
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
