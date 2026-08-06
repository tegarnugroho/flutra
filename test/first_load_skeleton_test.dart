import 'package:flutra/application/device/device_manager_cubit.dart';
import 'package:flutra/application/emulator/emulator_list_cubit.dart';
import 'package:flutra/application/flutter_sdk/flutter_sdk_cubit.dart';
import 'package:flutra/application/log/logcat_devices_cubit.dart';
import 'package:flutra/application/sdk/sdk_manager_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the rule that made screens flash their centred empty state before the
/// skeleton: the very first frame renders while the cubit is still `initial`,
/// so `isLoading` on its own is one frame too late.
void main() {
  group('isFirstLoad covers the frame before loading starts', () {
    test('device manager', () {
      const state = DeviceManagerState();
      expect(state.status, DeviceManagerStatus.initial);
      expect(state.isLoading, isFalse);
      expect(state.isFirstLoad, isTrue);
    });

    test('emulator list', () {
      const state = EmulatorListState();
      expect(state.isLoading, isFalse);
      expect(state.isFirstLoad, isTrue);
    });

    test('sdk manager', () {
      const state = SdkManagerState();
      expect(state.isLoading, isFalse);
      expect(state.isFirstLoad, isTrue);
    });

    test('flutter sdk', () {
      const state = FlutterSdkState();
      expect(state.isLoading, isFalse);
      expect(state.isFirstLoad, isTrue);
    });

    test('logcat devices', () {
      const state = LogcatDevicesState();
      expect(state.isLoading, isFalse);
      expect(state.isFirstLoad, isTrue);
      // The empty state must stay hidden until a load has actually run.
      expect(state.isEmpty, isFalse);
    });
  });

  group('isFirstLoad clears once the load settles', () {
    test('data ends it', () {
      const loaded = SdkManagerState(status: SdkManagerStatus.ready);
      expect(loaded.isFirstLoad, isFalse);
    });

    test('failure ends it', () {
      const failed = DeviceManagerState(status: DeviceManagerStatus.failure);
      expect(failed.isFirstLoad, isFalse);
    });

    test('an empty but finished logcat load ends it', () {
      const done = LogcatDevicesState(hasLoaded: true);
      expect(done.isFirstLoad, isFalse);
      expect(done.isEmpty, isTrue);
    });

    test('a refresh over existing data does not re-show the skeleton', () {
      const refreshing = EmulatorListState(
        status: EmulatorListStatus.loading,
        avds: [],
      );
      // No data yet — still the first load.
      expect(refreshing.isFirstLoad, isTrue);
    });
  });
}
