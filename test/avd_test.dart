import 'package:flutra/domain/entities/avd.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanizeImageTag', () {
    test('names the images developers actually pick between', () {
      expect(humanizeImageTag('google_apis_playstore'), 'Play Store');
      expect(humanizeImageTag('google_apis'), 'Google APIs');
      expect(humanizeImageTag('default'), 'AOSP');
    });

    test('ignores case and stray whitespace from the AVD config', () {
      expect(humanizeImageTag('  Google_APIs_Playstore '), 'Play Store');
    });

    test('an unmapped tag is shown as it came', () {
      // Inventing a label would hide which image type it actually is.
      expect(humanizeImageTag('android-automotive'), 'android-automotive');
    });

    test('an AVD with no tag has no image segment at all', () {
      expect(const Avd(name: 'x').displayImageType, isNull);
      expect(
        const Avd(name: 'x', tag: 'google_apis').displayImageType,
        'Google APIs',
      );
    });
  });

  group('avdDeviceKind', () {
    AvdDeviceKind kind(String name, {String? id, String? device}) =>
        avdDeviceKind(id, device, name);

    test('a phone profile is the default', () {
      expect(kind('Pixel_8', id: 'pixel_8', device: 'Pixel 8'),
          AvdDeviceKind.phone);
      expect(kind('My_AVD'), AvdDeviceKind.phone);
    });

    test('tablets are read from the id, the device name or the AVD name', () {
      expect(kind('X', id: 'pixel_tablet'), AvdDeviceKind.tablet);
      expect(kind('X', device: 'Pixel Tablet'), AvdDeviceKind.tablet);
      expect(kind('Work_Tablet_API_34'), AvdDeviceKind.tablet);
    });

    test('the Nexus and Pixel C tablets say so nowhere else', () {
      expect(kind('X', id: 'Nexus 10'), AvdDeviceKind.tablet);
      expect(kind('X', id: 'nexus_9'), AvdDeviceKind.tablet);
      expect(kind('X', id: 'pixel_c'), AvdDeviceKind.tablet);
      // Nexus 5 and 6 are phones — the pattern must not swallow them.
      expect(kind('X', id: 'Nexus 5'), AvdDeviceKind.phone);
      expect(kind('X', id: 'nexus_6'), AvdDeviceKind.phone);
    });

    test('TV and Wear win over anything phone-shaped', () {
      expect(kind('X', id: 'tv_1080p'), AvdDeviceKind.tv);
      expect(kind('Android TV (1080p)'), AvdDeviceKind.tv);
      expect(kind('X', id: 'wear_round'), AvdDeviceKind.wear);
      expect(kind('Galaxy Watch'), AvdDeviceKind.wear);
    });

    test('a word merely containing "tv" is not a television', () {
      expect(kind('X', device: 'Pixel Native'), AvdDeviceKind.phone);
    });
  });
}
