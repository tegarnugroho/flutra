import 'package:android_sdk_manager/application/emulator/create_emulator_cubit.dart';
import 'package:android_sdk_manager/domain/entities/device_definition.dart';
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

Future<CreateEmulatorCubit> loadedCubit() async {
  final cubit = CreateEmulatorCubit(
    _FakeEmulatorRepository(_devices, _images),
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
}
