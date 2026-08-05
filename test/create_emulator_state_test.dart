import 'package:android_sdk_manager/application/emulator/create_emulator_cubit.dart';
import 'package:android_sdk_manager/domain/entities/system_image.dart';
import 'package:flutter_test/flutter_test.dart';

SystemImage _img(int api, String tag, String abi) => SystemImage(
      packagePath: 'system-images;android-$api;$tag;$abi',
      platform: 'android-$api',
      apiLevel: api,
      tag: tag,
      abi: abi,
    );

void main() {
  final images = [
    _img(34, 'google_apis', 'x86_64'),
    _img(34, 'google_apis_playstore', 'x86_64'),
    _img(35, 'google_apis', 'arm64-v8a'),
    _img(35, 'google_apis', 'x86_64'),
  ];

  group('CreateEmulatorState derivations', () {
    test('availableApiLevels are distinct and newest-first', () {
      final state = CreateEmulatorState(images: images);
      expect(state.availableApiLevels, [35, 34]);
    });

    test('tagsForApi filters by selected API level', () {
      final state = CreateEmulatorState(images: images, apiLevel: 34);
      expect(state.tagsForApi, ['google_apis', 'google_apis_playstore']);
    });

    test('abisForSelection filters by API level and tag', () {
      final state = CreateEmulatorState(
        images: images,
        apiLevel: 35,
        tag: 'google_apis',
      );
      expect(state.abisForSelection, ['arm64-v8a', 'x86_64']);
    });

    test('selectedImage resolves only when fully specified', () {
      final incomplete = CreateEmulatorState(
        images: images,
        apiLevel: 35,
        tag: 'google_apis',
      );
      expect(incomplete.selectedImage, isNull);

      final complete = CreateEmulatorState(
        images: images,
        apiLevel: 35,
        tag: 'google_apis',
        abi: 'x86_64',
      );
      expect(complete.selectedImage?.packagePath,
          'system-images;android-35;google_apis;x86_64');
    });

    test('canAdvance gates each step on its required selection', () {
      const base = CreateEmulatorState();
      expect(base.canAdvance, isFalse); // device step, no device

      // A device picked while the category picker is showing is not enough:
      // step 1 only advances from its device-list phase.
      final onCategories = base.copyWith(deviceId: 'pixel_6');
      expect(onCategories.canAdvance, isFalse);

      final device = onCategories.copyWith(
        devicePhase: DeviceStepPhase.devices,
      );
      expect(device.canAdvance, isTrue);

      final configIncompleteName = CreateEmulatorState(
        images: images,
        step: WizardStep.configure,
        apiLevel: 35,
        tag: 'google_apis',
        abi: 'x86_64',
        name: '   ',
      );
      expect(configIncompleteName.canAdvance, isFalse); // blank name
    });
  });
}
