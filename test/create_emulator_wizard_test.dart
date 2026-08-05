import 'dart:async';

import 'package:android_sdk_manager/application/emulator/create_emulator_cubit.dart';
import 'package:android_sdk_manager/domain/entities/avd.dart';
import 'package:android_sdk_manager/domain/entities/avd_create_request.dart';
import 'package:android_sdk_manager/domain/entities/device_definition.dart';
import 'package:android_sdk_manager/domain/entities/sdk_package.dart';
import 'package:android_sdk_manager/domain/repositories/sdk_repository.dart';
import 'package:android_sdk_manager/infrastructure/system/host_info_service.dart';
import 'package:android_sdk_manager/domain/entities/system_image.dart';
import 'package:android_sdk_manager/domain/repositories/emulator_repository.dart';
import 'package:android_sdk_manager/presentation/emulator/widgets/device_step.dart';
import 'package:android_sdk_manager/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a fixed catalog so the wizard's derivations can be asserted exactly.
class _FakeEmulatorRepository implements EmulatorRepository {
  _FakeEmulatorRepository(this.devices, this.images);

  final List<DeviceDefinition> devices;
  final List<SystemImage> images;

  @override
  Future<List<DeviceDefinition>> listDeviceDefinitions() async => devices;

  @override
  Future<List<SystemImage>> listSystemImages() async => images;

  @override
  Future<List<Avd>> listAvds() async => const [];

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Host facts the tests control, so preset caps are deterministic.
class _FakeHostInfo implements HostInfoService {
  const _FakeHostInfo();

  /// A roomy but ordinary developer machine, so the preset caps are exercised
  /// rather than skipped.
  static const cores = 8;
  static const ramMb = 16384;

  @override
  Future<HostInfo> info() async =>
      const HostInfo(cores: cores, totalRamMb: ramMb);

  @override
  Future<int?> freeSpaceMb(String path) async => null;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

const _devices = <DeviceDefinition>[
  DeviceDefinition(id: 'pixel_6', name: 'Pixel 6', oem: 'Google'),
  DeviceDefinition(id: 'pixel_8', name: 'Pixel 8', oem: 'Google'),
  DeviceDefinition(id: 'nexus_9', name: 'Nexus 9 Tablet', oem: 'Google'),
  DeviceDefinition(id: 'wear_round', name: 'Wear OS Round', oem: 'Google'),
  DeviceDefinition(id: 'tv_1080p', name: 'Android TV (1080p)', oem: 'Google'),
];

const _images = <SystemImage>[
  SystemImage(
    packagePath: 'system-images;android-34;google_apis;x86_64',
    platform: 'android-34',
    apiLevel: 34,
    tag: 'google_apis',
    abi: 'x86_64',
  ),
];

/// Serves the sdkmanager catalogue: everything the wizard can offer, whether
/// or not it is on disk.
class _FakeSdkRepository implements SdkRepository {
  _FakeSdkRepository(this.packages);

  final List<SdkPackage> packages;

  @override
  Future<List<SdkPackage>> listPackages() async => packages;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

SdkPackage _pkg(String path, PackageState state) =>
    SdkPackage(path: path, description: path, state: state);

final _packages = <SdkPackage>[
  _pkg('system-images;android-34;google_apis;x86_64', PackageState.installed),
  _pkg('system-images;android-35;google_apis;x86_64', PackageState.available),
  _pkg('system-images;android-35;google_apis;arm64-v8a', PackageState.available),
  _pkg(
    'system-images;android-35;google_apis_playstore;x86_64',
    PackageState.available,
  ),
  _pkg('system-images;android-33;default;x86_64', PackageState.available),
  // Non-image and unparseable rows must never reach the wizard's lists.
  _pkg('platform-tools', PackageState.installed),
  _pkg(
    'system-images;android-TiramisuPrivacySandbox;google_apis;x86_64',
    PackageState.available,
  ),
];

Future<CreateEmulatorCubit> loadedCubit() async {
  final cubit = CreateEmulatorCubit(
    _FakeEmulatorRepository(_devices, _images),
    _FakeSdkRepository(_packages),
    _FakeHostInfo(),
  );
  await cubit.load();
  return cubit;
}

void main() {
  group('device categories', () {
    test('are derived from the catalog and skip empty buckets', () async {
      final cubit = await loadedCubit();
      final state = cubit.state;

      expect(state.deviceCategories, [
        DeviceCategory.phone,
        DeviceCategory.tablet,
        DeviceCategory.wear,
        DeviceCategory.tv,
      ]);
      expect(state.deviceCategoryCounts[DeviceCategory.phone], 2);
      expect(state.deviceCategoryCounts[DeviceCategory.tablet], 1);
      // Nothing in the catalog is automotive or foldable, so neither renders.
      expect(state.deviceCategoryCounts.containsKey(DeviceCategory.automotive),
          isFalse);
      expect(state.deviceCategories.length, state.deviceCategoryCounts.length);
    });
  });

  group('step 1 phases', () {
    test('opens on the category picker with no device list', () async {
      final cubit = await loadedCubit();
      expect(cubit.state.devicePhase, DeviceStepPhase.categories);
      expect(cubit.state.browsingCategory, isNull);
      expect(cubit.state.browsedDevices, isEmpty);
    });

    test('a category scopes the list and resets the search', () async {
      final cubit = await loadedCubit();
      cubit.openDeviceCategory(DeviceCategory.phone);
      cubit.setDeviceQuery('pixel 8');
      expect(cubit.state.browsedDevices.map((d) => d.id), ['pixel_8']);

      cubit.openDeviceCategory(DeviceCategory.tablet);
      expect(cubit.state.deviceQuery, isEmpty);
      expect(cubit.state.browsedDevices.map((d) => d.id), ['nexus_9']);
    });

    test('search matches the manufacturer too', () async {
      final cubit = await loadedCubit();
      cubit.openDeviceCategory(DeviceCategory.phone);
      cubit.setDeviceQuery('google');
      expect(cubit.state.browsedDevices, hasLength(2));
      cubit.setDeviceQuery('nothing here');
      expect(cubit.state.browsedDevices, isEmpty);
    });

    test('a category alone never lets the wizard advance', () async {
      final cubit = await loadedCubit();
      expect(cubit.state.canAdvance, isFalse);

      cubit.openDeviceCategory(DeviceCategory.phone);
      expect(cubit.state.canAdvance, isFalse);

      cubit.selectDevice('pixel_6');
      expect(cubit.state.canAdvance, isTrue);

      // Back on the categories screen the selection stands but Next does not.
      cubit.showDeviceCategories();
      expect(cubit.state.deviceId, 'pixel_6');
      expect(cubit.state.canAdvance, isFalse);
    });

    test('the selection survives switching categories', () async {
      final cubit = await loadedCubit();
      cubit.openDeviceCategory(DeviceCategory.phone);
      cubit.selectDevice('pixel_6');

      cubit.openDeviceCategory(DeviceCategory.tv);
      expect(cubit.state.deviceId, 'pixel_6');
      expect(cubit.state.selectedDevice?.name, 'Pixel 6');
    });
  });

  group('back semantics', () {
    test('device list falls back to categories before leaving', () async {
      final cubit = await loadedCubit();
      cubit.openDeviceCategory(DeviceCategory.phone);

      expect(cubit.back(), isTrue);
      expect(cubit.state.devicePhase, DeviceStepPhase.categories);

      // Nowhere left inside the wizard — the page decides what to do.
      expect(cubit.back(), isFalse);
      expect(cubit.state.step, WizardStep.device);
    });

    test('returning from step 2 restores the selected device category',
        () async {
      final cubit = await loadedCubit();
      cubit.openDeviceCategory(DeviceCategory.tablet);
      cubit.selectDevice('nexus_9');
      cubit.next();
      expect(cubit.state.step, WizardStep.apiLevel);

      expect(cubit.back(), isTrue);
      expect(cubit.state.step, WizardStep.device);
      expect(cubit.state.devicePhase, DeviceStepPhase.devices);
      expect(cubit.state.browsingCategory, DeviceCategory.tablet);
      expect(cubit.state.deviceId, 'nexus_9');
    });

    test('jumping back to step 1 via the stepper lands on the device list',
        () async {
      final cubit = await loadedCubit();
      cubit.openDeviceCategory(DeviceCategory.phone);
      cubit.selectDevice('pixel_6');
      cubit.next();
      cubit.selectApiLevel(34);
      cubit.next();

      cubit.goTo(WizardStep.device);
      expect(cubit.state.devicePhase, DeviceStepPhase.devices);
      expect(cubit.state.browsingCategory, DeviceCategory.phone);
    });

    test('a wizard with no device picked goes straight to categories',
        () async {
      final cubit = await loadedCubit();
      cubit.goTo(WizardStep.apiLevel);
      cubit.goTo(WizardStep.device);
      expect(cubit.state.devicePhase, DeviceStepPhase.categories);
    });
  });

  group('device step layout', () {
    /// The wizard window is roughly this wide; the grids must fit the cards at
    /// both column counts without the rows growing with the window.
    const widths = <double>[720, 880, 900, 1100, 1600];

    Widget host(CreateEmulatorCubit cubit, ThemeMode mode) => FluentApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: BlocProvider.value(
        value: cubit,
        child: ScaffoldPage(
          padding: const EdgeInsets.all(24),
          content: BlocBuilder<CreateEmulatorCubit, CreateEmulatorState>(
            builder: (context, state) => DeviceStep(state: state),
          ),
        ),
      ),
    );

    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      for (final width in widths) {
        testWidgets('lays out at ${width}px, ${mode.name}', (tester) async {
          tester.view.physicalSize = Size(width, 760);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final cubit = await loadedCubit();
          addTearDown(cubit.close);

          await tester.pumpWidget(host(cubit, mode));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'category picker');

          cubit.openDeviceCategory(DeviceCategory.phone);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'device list');

          cubit.selectDevice('pixel_6');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'selected card');
        });
      }
    }

    testWidgets('cards keep a fixed height as the window grows',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final cubit = await loadedCubit();
      addTearDown(cubit.close);

      final heights = <double>[];
      for (final width in [960.0, 1600.0]) {
        tester.view.physicalSize = Size(width, 760);
        await tester.pumpWidget(host(cubit, ThemeMode.dark));
        await tester.pumpAndSettle();
        heights.add(tester.getSize(find.byType(GridView)).height);
        final card = find.descendant(
          of: find.byType(GridView),
          matching: find.byType(FocusableActionDetector),
        );
        heights.add(tester.getSize(card.first).height);
      }
      // Same card height at both widths — the grid must not scale the rows.
      expect(heights[1], heights[3]);
    });
  });

  group('image catalogue', () {
    test('offers packages that are not installed yet', () async {
      final cubit = await loadedCubit();
      final state = cubit.state;

      // API 35 has no local image at all and must still be listed.
      expect(state.availableApiLevels, [35, 34, 33]);
      expect(state.isApiInstalled(34), isTrue);
      expect(state.isApiInstalled(35), isFalse);
      expect(state.isApiInstalled(33), isFalse);
    });

    test('drops non-image and unparseable package paths', () async {
      final cubit = await loadedCubit();
      final paths = cubit.state.options.map((o) => o.packagePath);

      expect(paths, isNot(contains('platform-tools')));
      expect(
        paths.where((p) => p.contains('TiramisuPrivacySandbox')),
        isEmpty,
        reason: 'a non-numeric API level has no place in the version list',
      );
    });

    test('an image on disk counts as installed even if the catalogue lags',
        () async {
      // _images (the emulator repo's on-disk scan) reports API 34, which the
      // sdkmanager fixture also lists as installed; the merge must not
      // downgrade it.
      final cubit = await loadedCubit();
      final option = cubit.state.options.firstWhere(
        (o) => o.packagePath == 'system-images;android-34;google_apis;x86_64',
      );
      expect(option.installed, isTrue);
    });

    test('flavours and ABIs come from the selected API only', () async {
      final cubit = await loadedCubit();
      cubit.selectApiLevel(35);
      expect(cubit.state.tagsForApi, [
        'google_apis',
        'google_apis_playstore',
      ]);

      cubit.selectTag('google_apis');
      expect(cubit.state.abisForSelection, ['arm64-v8a', 'x86_64']);

      cubit.selectTag('google_apis_playstore');
      expect(cubit.state.abisForSelection, ['x86_64']);
    });

    test('install state is per exact package at the ABI step', () async {
      final cubit = await loadedCubit();
      cubit.selectApiLevel(34);
      cubit.selectTag('google_apis');
      expect(cubit.state.optionForAbi('x86_64')?.installed, isTrue);

      cubit.selectApiLevel(35);
      cubit.selectTag('google_apis');
      expect(cubit.state.optionForAbi('x86_64')?.installed, isFalse);
      expect(cubit.state.optionForAbi('arm64-v8a')?.installed, isFalse);
    });

    test('needsDownload tracks the fully-specified selection', () async {
      final cubit = await loadedCubit();
      cubit.selectApiLevel(35);
      cubit.selectTag('google_apis');
      // No ABI yet — nothing to say.
      expect(cubit.state.selectedOption, isNull);
      expect(cubit.state.needsDownload, isFalse);

      cubit.selectAbi('x86_64');
      expect(cubit.state.needsDownload, isTrue);

      cubit.selectApiLevel(34);
      cubit.selectTag('google_apis');
      cubit.selectAbi('x86_64');
      expect(cubit.state.needsDownload, isFalse);
    });

    test('older levels sit behind the expander', () async {
      final cubit = await loadedCubit();
      // The fixture has fewer levels than the cut-off, so all are visible.
      expect(cubit.state.olderApiLevels, isEmpty);
      expect(
        cubit.state.visibleApiLevels,
        cubit.state.availableApiLevels,
      );

      final many = CreateEmulatorState(
        options: [
          for (var api = 20; api < 40; api++)
            ImageOption(
              packagePath: 'system-images;android-$api;google_apis;x86_64',
              apiLevel: api,
              tag: 'google_apis',
              abi: 'x86_64',
              installed: false,
            ),
        ],
      );
      expect(
        many.visibleApiLevels,
        hasLength(CreateEmulatorState.recentApiCount),
      );
      expect(many.visibleApiLevels.first, 39, reason: 'newest first');
      expect(many.olderApiLevels, isNotEmpty);
      expect(
        many.copyWith(showOlderApis: true).visibleApiLevels,
        many.availableApiLevels,
      );
    });
  });

  group('android version naming', () {
    test('names the levels the emulator still ships', () {
      expect(androidVersionOf(35).version, 'Android 15');
      expect(androidVersionOf(35).codename, 'VanillaIceCream');
      expect(androidVersionOf(34).codename, 'UpsideDownCake');
    });

    test('falls back to the bare level for anything unnamed', () {
      expect(androidVersionOf(19).version, 'API 19');
      expect(androidVersionOf(19).codename, isNull);
    });
  });

  group('load concurrency', () {
    /// Repositories that never complete on their own, so the test can see
    /// exactly which calls were issued before any of them returned.
    test('starts every catalogue query before awaiting one', () async {
      final packages = Completer<List<SdkPackage>>();
      final images = Completer<List<SystemImage>>();
      final devices = Completer<List<DeviceDefinition>>();

      final cubit = CreateEmulatorCubit(
        _BlockingEmulatorRepository(images: images, devices: devices),
        _BlockingSdkRepository(packages),
        _FakeHostInfo(),
      );
      addTearDown(cubit.close);

      final load = cubit.load();
      // One microtask turn is enough for load() to reach its first await.
      await Future<void>.delayed(Duration.zero);

      // All three JVM/disk calls must already be in flight. If load() chained
      // them, only the first would have been touched by now.
      expect(packages.isCompleted, isFalse);
      expect(
        _BlockingSdkRepository.started,
        isTrue,
        reason: 'sdkmanager --list not started',
      );
      expect(
        _BlockingEmulatorRepository.imagesStarted,
        isTrue,
        reason: 'on-disk image scan not started',
      );
      expect(
        _BlockingEmulatorRepository.devicesStarted,
        isTrue,
        reason: 'avdmanager list device not started — it was chained',
      );

      packages.complete(_packages);
      images.complete(const []);
      devices.complete(_devices);
      await load;
      expect(cubit.state.loadStatus, LoadStatus.ready);
    });
  });

  group('presets', () {
    test('balanced is the starting point and respects host caps', () async {
      final cubit = await loadedCubit();
      final config = cubit.state.config;

      expect(cubit.state.preset, EmulatorPreset.balanced);
      expect(config.ramMb, 2048);
      expect(config.internalStorageMb, 6144);
      // Half of the fake host's 8 cores.
      expect(config.cpuCores, 4);
      expect(config.gpuMode, GpuMode.auto);
    });

    test('performance caps RAM at a quarter of the host', () {
      final onSmallHost = configForPreset(
        EmulatorPreset.performance,
        null,
        hostCores: 8,
        hostRamMb: 8192,
      );
      // 4096 would be half the machine; the cap pulls it to 2048.
      expect(onSmallHost.ramMb, 2048);
      expect(onSmallHost.cpuCores, 6);
      expect(onSmallHost.gpuMode, GpuMode.host);

      final onBigHost = configForPreset(
        EmulatorPreset.performance,
        null,
        hostCores: 4,
        hostRamMb: 65536,
      );
      expect(onBigHost.ramMb, 4096, reason: 'baseline, not host/4');
      expect(onBigHost.cpuCores, 2, reason: 'host - 2');
    });

    test('unknown host facts skip the caps instead of guessing', () {
      final blind = configForPreset(EmulatorPreset.performance, null);
      expect(blind.ramMb, 4096);
      expect(blind.cpuCores, 6);
    });

    test('lean form factors get smaller baselines', () {
      final wear = configForPreset(
        EmulatorPreset.balanced,
        DeviceCategory.wear,
        hostCores: 8,
      );
      final phone = configForPreset(
        EmulatorPreset.balanced,
        DeviceCategory.phone,
        hostCores: 8,
      );
      expect(wear.ramMb, lessThan(phone.ramMb));

      final wearMinimal = configForPreset(
        EmulatorPreset.minimal,
        DeviceCategory.wear,
      );
      expect(wearMinimal.ramMb, 512);
    });

    test('editing a field flips the control to Custom', () async {
      final cubit = await loadedCubit();
      cubit.updateConfig(cubit.state.config.copyWith(ramMb: 3072));

      expect(cubit.state.preset, EmulatorPreset.custom);
      expect(cubit.state.config.ramMb, 3072, reason: 'the edit is kept');

      // Picking a baseline again overwrites everything, advanced included.
      cubit.selectPreset(EmulatorPreset.minimal);
      expect(cubit.state.preset, EmulatorPreset.minimal);
      expect(cubit.state.config.ramMb, 1024);
      expect(cubit.state.config.sdCardMb, 0);
      expect(cubit.state.config.vmHeapMb, 256);
    });

    test('the advanced section remembers its state', () async {
      final cubit = await loadedCubit();
      expect(cubit.state.advancedExpanded, isFalse);
      cubit.toggleAdvanced();
      expect(cubit.state.advancedExpanded, isTrue);
    });
  });

  group('create validation', () {
    Future<CreateEmulatorCubit> readyToCreate() async {
      final cubit = await loadedCubit();
      cubit.openDeviceCategory(DeviceCategory.phone);
      cubit.selectDevice('pixel_6');
      cubit.selectApiLevel(34);
      cubit.selectTag('google_apis');
      cubit.selectAbi('x86_64');
      return cubit;
    }

    test('a complete selection can be created', () async {
      final cubit = await readyToCreate();
      cubit.setName('Pixel_6_API_34');
      expect(cubit.state.nameError, isNull);
      expect(cubit.state.createBlockedReason, isNull);
    });

    test('rejects an empty or badly-charactered name', () async {
      final cubit = await readyToCreate();

      cubit.setName('   ');
      expect(cubit.state.nameError, 'Enter a name');

      cubit.setName('Pixel 6!');
      expect(cubit.state.nameError, contains('letters, numbers'));
      expect(cubit.state.createBlockedReason, isNotNull);
    });

    test('rejects a name another AVD already holds', () async {
      final cubit = await readyToCreate();
      final taken = cubit.state.copyWith(existingAvdNames: {'Pixel_6_API_34'});
      expect(
        taken.copyWith(name: 'Pixel_6_API_34').nameError,
        'An AVD with this name already exists',
      );
      expect(taken.copyWith(name: 'Something_Else').nameError, isNull);
    });

    test('blocks on the first problem, earlier steps first', () {
      const nothing = CreateEmulatorState();
      expect(nothing.createBlockedReason, 'Finish the earlier steps first');
    });

    test('disk needed is storage plus SD card, image excluded', () async {
      final cubit = await readyToCreate();
      cubit.updateConfig(
        cubit.state.config.copyWith(internalStorageMb: 6144, sdCardMb: 512),
      );
      expect(cubit.state.diskNeededMb, 6656);
      expect(cubit.state.diskTooSmall, isFalse, reason: 'free space unknown');

      final cramped = cubit.state.copyWith(freeDiskMb: 1024);
      expect(cramped.diskTooSmall, isTrue);
      expect(cramped.createBlockedReason, 'Not enough free disk space');
    });
  });
}

class _BlockingSdkRepository implements SdkRepository {
  _BlockingSdkRepository(this._packages) {
    started = false;
  }

  static bool started = false;
  final Completer<List<SdkPackage>> _packages;

  @override
  Future<List<SdkPackage>> listPackages() {
    started = true;
    return _packages.future;
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _BlockingEmulatorRepository implements EmulatorRepository {
  _BlockingEmulatorRepository({required this.images, required this.devices}) {
    imagesStarted = false;
    devicesStarted = false;
  }

  static bool imagesStarted = false;
  static bool devicesStarted = false;

  final Completer<List<SystemImage>> images;
  final Completer<List<DeviceDefinition>> devices;

  @override
  Future<List<SystemImage>> listSystemImages() {
    imagesStarted = true;
    return images.future;
  }

  @override
  Future<List<DeviceDefinition>> listDeviceDefinitions() {
    devicesStarted = true;
    return devices.future;
  }

  @override
  Future<List<Avd>> listAvds() async => const [];

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}