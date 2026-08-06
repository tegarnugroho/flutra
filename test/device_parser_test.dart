import 'package:flutra/domain/entities/device.dart';
import 'package:flutra/infrastructure/repositories/device_repository_impl.dart';
import 'package:flutra/infrastructure/repositories/flutter_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = '''
List of devices attached
emulator-5554          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64x transport_id:1
0A281FDD40012345       device product:redfin model:Pixel_5 device:redfin transport_id:2
192.168.1.50:5555      offline
R58NABCDEFG            unauthorized
''';

void main() {
  group('DeviceRepositoryImpl.parseDevices', () {
    final devices = DeviceRepositoryImpl.parseDevices(_sample);
    Device bySerial(String s) => devices.firstWhere((d) => d.serial == s);

    test('parses each attached device', () {
      expect(devices.length, 4);
    });

    test('reads state and long-format fields', () {
      final pixel = bySerial('0A281FDD40012345');
      expect(pixel.state, DeviceState.device);
      expect(pixel.model, 'Pixel_5');
      expect(pixel.product, 'redfin');
      expect(pixel.transportId, '2');
    });

    test('classifies emulator, network and usb devices', () {
      expect(bySerial('emulator-5554').isEmulator, isTrue);
      expect(bySerial('192.168.1.50:5555').isNetwork, isTrue);
      expect(bySerial('0A281FDD40012345').isEmulator, isFalse);
    });

    test('maps offline and unauthorized states', () {
      expect(bySerial('192.168.1.50:5555').state, DeviceState.offline);
      expect(bySerial('R58NABCDEFG').state, DeviceState.unauthorized);
      expect(bySerial('R58NABCDEFG').state.isOnline, isFalse);
    });

    test('displayName prefers a humanised model', () {
      expect(bySerial('0A281FDD40012345').displayName, 'Pixel 5');
    });
  });

  group('FlutterRepositoryImpl.parseFlutterDevices', () {
    const json = '''
[
  {"name":"sdk gphone64 x86 64","id":"emulator-5554","targetPlatform":"android-x64","emulator":true},
  {"name":"Windows","id":"windows","targetPlatform":"windows-x64","emulator":false},
  {"name":"Chrome","id":"chrome","targetPlatform":"web-javascript","emulator":false}
]''';

    final devices = FlutterRepositoryImpl.parseFlutterDevices(json);

    test('parses every flutter target', () {
      expect(devices.map((d) => d.serial),
          containsAll(['emulator-5554', 'windows', 'chrome']));
    });

    test('flags adb support only for Android targets', () {
      expect(devices.firstWhere((d) => d.serial == 'emulator-5554').supportsAdb,
          isTrue);
      expect(
          devices.firstWhere((d) => d.serial == 'windows').supportsAdb, isFalse);
      expect(
          devices.firstWhere((d) => d.serial == 'chrome').supportsAdb, isFalse);
    });

    test('exposes friendly platform labels', () {
      expect(devices.firstWhere((d) => d.serial == 'windows').platformLabel,
          'Windows');
      expect(devices.firstWhere((d) => d.serial == 'chrome').platformLabel,
          'Web');
    });

    test('tolerates leading warnings before the JSON array', () {
      final withNoise =
          'Warning: something\n$json';
      expect(FlutterRepositoryImpl.parseFlutterDevices(withNoise), isNotEmpty);
    });
  });
}
