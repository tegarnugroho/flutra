import 'package:flutra/application/emulator/emulator_list_cubit.dart';
import 'package:flutra/domain/entities/avd.dart';
import 'package:flutra/presentation/emulator/widgets/avd_tile.dart';
import 'package:flutra/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => FluentApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: ThemeMode.dark,
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: SizedBox(width: 900, child: child),
  ),
);

const _pixel = Avd(
  name: 'Pixel_8_API_34',
  deviceName: 'Pixel 8',
  deviceId: 'pixel_8',
  androidVersion: '14.0',
  apiLevel: 34,
  tag: 'google_apis_playstore',
  abi: 'x86_64',
  path: r'C:\Users\me\.android\avd\Pixel_8_API_34.avd',
);

Widget _tile(
  Avd avd, {
  AvdTask? task,
  VoidCallback? onStart,
  VoidCallback? onStop,
  VoidCallback? onDelete,
  bool showInFolder = true,
}) => AvdTile(
  avd: avd,
  task: task,
  onStart: onStart ?? () {},
  onColdBoot: () {},
  onStop: onStop ?? () {},
  onWipe: () {},
  onDelete: onDelete ?? () {},
  onDuplicate: () {},
  onConsole: () {},
  onShowInFolder: showInFolder ? () {} : null,
);

void main() {
  group('device tile', () {
    testWidgets('a stopped device leads with Start, the page\'s main action',
        (tester) async {
      var started = 0;
      await tester.pumpWidget(
        _host(_tile(_pixel, onStart: () => started++)),
      );

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('running'), findsNothing);

      await tester.tap(find.text('Start'));
      expect(started, 1);
    });

    testWidgets('the meta line humanises the image and keeps the API level',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_pixel)));

      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('Android 14.0 (API 34)'), findsOneWidget);
      expect(find.text('Play Store'), findsOneWidget);
      expect(find.text('x86_64'), findsOneWidget);
      // The raw tag is one hover away, because sdkmanager paths use it.
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('Play Store'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'System image tag: google_apis_playstore');
    });

    testWidgets('a running device shows the pill and offers Stop',
        (tester) async {
      var stopped = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            _pixel.copyWith(isRunning: true),
            onStop: () => stopped++,
          ),
        ),
      );

      expect(find.text('running'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Start'), findsNothing);

      await tester.tap(find.text('Stop'));
      expect(stopped, 1);
    });

    testWidgets('an in-flight device says what it is doing and takes no taps',
        (tester) async {
      var started = 0;
      await tester.pumpWidget(
        _host(
          _tile(_pixel, task: AvdTask.starting, onStart: () => started++),
        ),
      );

      expect(find.text('Starting…'), findsOneWidget);
      expect(find.text('Start'), findsNothing);
      // Neither running nor stopped, so no pill claims either.
      expect(find.text('running'), findsNothing);

      await tester.tap(find.text('Starting…'));
      expect(started, 0);
    });

    testWidgets('the busy pulse stops when the OS asks for reduced motion',
        (tester) async {
      Widget host({required bool reducedMotion}) => MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: _host(_tile(_pixel, task: AvdTask.starting)),
      );

      await tester.pumpWidget(host(reducedMotion: true));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(host(reducedMotion: false));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('the icon square follows the device family', (tester) async {
      await tester.pumpWidget(_host(_tile(_pixel)));
      expect(find.byIcon(FluentIcons.cell_phone), findsOneWidget);

      await tester.pumpWidget(
        _host(_tile(const Avd(name: 'Tab', deviceId: 'pixel_tablet'))),
      );
      expect(find.byIcon(FluentIcons.tablet), findsOneWidget);
    });

    testWidgets('the menu groups run, management and destructive actions',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_pixel)));
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      expect(find.text('Cold boot'), findsOneWidget);
      expect(find.text('Emulator console'), findsNothing);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Show in folder'), findsOneWidget);
      expect(find.text('Wipe data'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Run variant, then management, then the two destructive ones last —
      // the grouping is the point, so it is the order that is asserted.
      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(y('Cold boot'), lessThan(y('Duplicate')));
      expect(y('Duplicate'), lessThan(y('Show in folder')));
      expect(y('Show in folder'), lessThan(y('Wipe data')));
      expect(y('Wipe data'), lessThan(y('Delete')));
    });

    testWidgets('a running device trades Cold boot for the console',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_pixel.copyWith(isRunning: true))));
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      expect(find.text('Emulator console'), findsOneWidget);
      expect(find.text('Cold boot'), findsNothing);
    });

    testWidgets('Delete is refused while the device is up', (tester) async {
      var deleted = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            _pixel.copyWith(isRunning: true),
            onDelete: () => deleted++,
          ),
        ),
      );
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, 0);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Stop the device first');
    });

    testWidgets('an AVD with no directory has no Show in folder',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_pixel, showInFolder: false)));
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      expect(find.text('Show in folder'), findsNothing);
      expect(find.text('Duplicate'), findsOneWidget);
    });
  });
}
