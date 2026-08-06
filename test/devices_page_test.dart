import 'package:flutra/application/device/device_manager_cubit.dart';
import 'package:flutra/domain/entities/device.dart';
import 'package:flutra/presentation/device/widgets/device_tile.dart';
import 'package:flutra/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 900}) => FluentApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: ThemeMode.dark,
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: SizedBox(width: width, child: child),
  ),
);

const _phone = Device(
  serial: 'emulator-5554',
  state: DeviceState.device,
  model: 'sdk_gphone64_x86_64',
  manufacturer: 'Google',
  androidRelease: '14',
  sdkInt: 34,
  batteryLevel: 100,
);

const _chrome = Device(
  serial: 'chrome',
  state: DeviceState.device,
  model: 'Chrome',
  platform: 'web-javascript',
  supportsAdb: false,
);

Widget _tile(
  Device device, {
  DeviceTask? task,
  VoidCallback? onShell,
  VoidCallback? onScreenshot,
  VoidCallback? onDisconnect,
  void Function(RebootTarget)? onReboot,
}) => DeviceTile(
  device: device,
  task: task,
  actions: DeviceActions(
    onShell: onShell ?? () {},
    onScreenshot: onScreenshot ?? () {},
    onInstallApk: () {},
    onLogcat: () {},
    onReboot: onReboot ?? (_) {},
    onDisconnect: onDisconnect ?? () {},
  ),
);

void main() {
  group('device tile', () {
    testWidgets('an online device leads with Shell and Screenshot',
        (tester) async {
      var shells = 0;
      var shots = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            _phone,
            onShell: () => shells++,
            onScreenshot: () => shots++,
          ),
        ),
      );

      expect(find.text('Shell'), findsOneWidget);
      await tester.tap(find.text('Shell'));
      await tester.tap(find.byIcon(FluentIcons.camera));
      expect(shells, 1);
      expect(shots, 1);
    });

    testWidgets('the meta line leads with the serial and its copy action',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_phone)));

      expect(find.text('emulator-5554'), findsOneWidget);
      // The tail is one run of text, so it is what gives first when the tile
      // narrows rather than overflowing it.
      expect(
        find.text(' · Google · Android 14 (API 34) · emulator · battery 100%'),
        findsOneWidget,
      );
      expect(find.byIcon(FluentIcons.copy), findsOneWidget);
      // The name is the model, cleaned up.
      expect(find.text('sdk gphone64 x86 64'), findsOneWidget);
    });

    testWidgets('online says nothing; the pill is for states that block you',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_phone)));
      expect(find.text('online'), findsNothing);

      await tester.pumpWidget(
        _host(_tile(const Device(serial: 'x', state: DeviceState.offline))),
      );
      expect(find.text('offline'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          _tile(const Device(serial: 'x', state: DeviceState.unauthorized)),
        ),
      );
      expect(find.text('unauthorized'), findsOneWidget);
    });

    testWidgets('an offline device offers no shell to open', (tester) async {
      await tester.pumpWidget(
        _host(_tile(const Device(serial: 'x', state: DeviceState.offline))),
      );

      expect(find.text('Shell'), findsNothing);
      expect(find.byIcon(FluentIcons.camera), findsNothing);
      // The kebab stays: disconnecting is exactly what an offline device needs.
      expect(find.byIcon(FluentIcons.more), findsOneWidget);
    });

    testWidgets('an in-flight device says what it is doing and takes no taps',
        (tester) async {
      var shots = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            _phone,
            task: DeviceTask.capturing,
            onScreenshot: () => shots++,
          ),
        ),
      );

      expect(find.text('Capturing…'), findsOneWidget);
      expect(find.text('Shell'), findsNothing);

      await tester.tap(find.text('Capturing…'));
      expect(shots, 0);
    });

    testWidgets('a Flutter-only target is badged and has no adb actions',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_chrome)));

      expect(find.text('Flutter target'), findsOneWidget);
      expect(find.textContaining('Web'), findsOneWidget);
      expect(find.text('Shell'), findsNothing);
      expect(find.byIcon(FluentIcons.more), findsNothing);
      expect(find.byIcon(FluentIcons.globe), findsOneWidget);
    });

    testWidgets('a narrow window ellipsizes the meta line, never overflows it',
        (tester) async {
      for (final width in const [720.0, 560.0, 420.0, 360.0]) {
        await tester.pumpWidget(
          _host(
            _tile(
              const Device(
                serial: '192.168.1.104:5555',
                state: DeviceState.device,
                model: 'Samsung Galaxy S24 Ultra Enterprise Edition',
                manufacturer: 'Samsung',
                androidRelease: '14',
                sdkInt: 34,
                batteryLevel: 87,
              ),
            ),
            width: width,
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at ${width}px');
      }
    });

    testWidgets('the menu groups push/read, reboots and the destructive one',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_phone)));
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(y('Install APK'), lessThan(y('Logcat')));
      expect(y('Logcat'), lessThan(y('Reboot')));
      expect(y('Reboot to recovery'), lessThan(y('Stop emulator')));
    });

    testWidgets('a real device is disconnected, an emulator is stopped',
        (tester) async {
      await tester.pumpWidget(
        _host(
          _tile(
            const Device(serial: '1A2B3C', state: DeviceState.device),
          ),
        ),
      );
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.text('Stop emulator'), findsNothing);
    });

    testWidgets('an offline device can still be dropped', (tester) async {
      var disconnected = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            const Device(serial: '1A2B3C', state: DeviceState.offline),
            onDisconnect: () => disconnected++,
          ),
        ),
      );
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      // Reboot needs a device that answers; disconnecting does not.
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(disconnected, 1);
    });

    testWidgets('an offline device is not rebooted', (tester) async {
      var reboots = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            const Device(serial: '1A2B3C', state: DeviceState.offline),
            onReboot: (_) => reboots++,
          ),
        ),
      );
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reboot'));
      await tester.pumpAndSettle();
      expect(reboots, 0);
    });
  });

  group('countLabel', () {
    DeviceManagerState stateOf(List<Device> devices) =>
        DeviceManagerState(devices: devices);

    test('counts devices, and offline ones only when there are some', () {
      expect(stateOf(const [_phone, _chrome]).countLabel, '2 devices');
      expect(
        stateOf(const [
          _phone,
          Device(serial: 'x', state: DeviceState.offline),
        ]).countLabel,
        '2 devices · 1 offline',
      );
    });

    test('one device is not "1 devices"', () {
      expect(stateOf(const [_phone]).countLabel, '1 device');
    });
  });
}
