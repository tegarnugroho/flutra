import 'package:flutra/domain/entities/sdk_package.dart';
import 'package:flutra/presentation/sdk/widgets/sdk_package_tile.dart';
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

const _available = SdkPackage(
  path: 'platforms;android-34',
  description: 'Android SDK Platform 34',
  state: PackageState.available,
  availableVersion: '3',
);

const _installed = SdkPackage(
  path: 'platform-tools',
  description: 'Android SDK Platform-Tools',
  state: PackageState.installed,
  installedVersion: '35.0.2',
);

const _updatable = SdkPackage(
  path: 'build-tools;35.0.0',
  description: 'Android SDK Build-Tools 35',
  state: PackageState.updatable,
  installedVersion: '34.0.0',
  availableVersion: '35.0.0',
);

Widget _tile(
  SdkPackage package, {
  bool checked = false,
  bool selected = false,
  bool queued = false,
  bool active = false,
  double? progress,
  VoidCallback? onInstall,
  VoidCallback? onUninstall,
  VoidCallback? onSelect,
}) => SdkPackageTile(
  package: package,
  checked: checked,
  selected: selected,
  queued: queued,
  active: active,
  progress: progress,
  onCheck: (_) {},
  onSelect: onSelect ?? () {},
  onInstall: onInstall ?? () {},
  onUninstall: onUninstall ?? () {},
);

void main() {
  group('package tile', () {
    testWidgets('a package that is not installed leads with Install',
        (tester) async {
      var installs = 0;
      await tester.pumpWidget(
        _host(_tile(_available, onInstall: () => installs++)),
      );

      expect(find.text('Android SDK Platform 34'), findsOneWidget);
      // The path is metadata now, not a suffix on the title.
      expect(find.text('platforms;android-34'), findsOneWidget);
      expect(find.text('Platforms'), findsOneWidget);

      await tester.tap(find.text('Install'));
      expect(installs, 1);
    });

    testWidgets('an update shows the jump it would make', (tester) async {
      await tester.pumpWidget(_host(_tile(_updatable)));

      expect(find.text('update available'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      final version = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && (w.textSpan?.toPlainText() ?? '').contains('→'),
        ),
      );
      expect(version.textSpan!.toPlainText(), '34.0.0 → 35.0.0');
    });

    testWidgets('an installed package is quiet — no pill, just the version',
        (tester) async {
      var uninstalls = 0;
      await tester.pumpWidget(
        _host(_tile(_installed, onUninstall: () => uninstalls++)),
      );

      expect(find.text('update available'), findsNothing);
      expect(find.text('installed'), findsNothing);
      expect(find.text('35.0.2'), findsOneWidget);

      await tester.tap(find.byIcon(FluentIcons.delete));
      expect(uninstalls, 1);
    });

    testWidgets('a queued package says so and offers no second click',
        (tester) async {
      var installs = 0;
      await tester.pumpWidget(
        _host(_tile(_available, queued: true, onInstall: () => installs++)),
      );

      expect(find.text('queued'), findsOneWidget);
      await tester.tap(find.text('Queued'));
      expect(installs, 0);
    });

    testWidgets('an installing package shows its progress under the row',
        (tester) async {
      await tester.pumpWidget(
        _host(_tile(_available, active: true, queued: true, progress: 0.42)),
      );

      expect(find.text('Installing…'), findsOneWidget);
      expect(find.byType(ProgressBar), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      // Active wins over queued: one state per tile.
      expect(find.text('queued'), findsNothing);
    });

    testWidgets('an install with no percentage yet still reads as working',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_available, active: true)));

      expect(find.text('Working…'), findsOneWidget);
    });

    testWidgets('tapping the tile opens it in the details panel',
        (tester) async {
      var selects = 0;
      await tester.pumpWidget(
        _host(_tile(_available, onSelect: () => selects++)),
      );

      await tester.tap(find.text('Android SDK Platform 34'));
      expect(selects, 1);
    });

    testWidgets('the version and its button sit against the right edge',
        (tester) async {
      await tester.pumpWidget(_host(_tile(_updatable)));

      final tile = tester.getRect(find.byType(SdkPackageTile));
      final button = tester.getRect(find.text('Update'));
      final version = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.textSpan?.toPlainText() ?? '').contains('→'),
        ),
      );

      // A Flexible version block would share the row's free space with the
      // title and leave both floating mid-tile, with empty room to the right.
      expect(tile.right - button.right, lessThan(60));
      expect(button.left - version.right, greaterThan(8));
      expect(version.left, greaterThan(tile.width / 2));
    });

    testWidgets('a narrow window ellipsizes rather than overflowing',
        (tester) async {
      for (final width in const [720.0, 560.0, 420.0, 360.0]) {
        await tester.pumpWidget(
          _host(
            _tile(
              const SdkPackage(
                path: 'system-images;android-34;google_apis_playstore;x86_64',
                description:
                    'Google Play Intel x86_64 Atom System Image for API 34',
                state: PackageState.updatable,
                installedVersion: '12',
                availableVersion: '13',
              ),
            ),
            width: width,
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at ${width}px');
      }
    });
  });
}
