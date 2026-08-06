import 'package:flutra/application/java/java_cubit.dart';
import 'package:flutra/domain/entities/jdk.dart';
import 'package:flutra/presentation/java/widgets/java_identity_panel.dart';
import 'package:flutra/presentation/java/widgets/jdk_tile.dart';
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

const _adoptium = Jdk(
  path: r'C:\Program Files\Eclipse Adoptium\jdk-17.0.11-hotspot',
  source: JdkSource.registry,
  version: '17.0.11',
  vendor: 'Eclipse Adoptium',
  arch: 'x86_64',
);

const _jbr = Jdk(
  path: r'C:\Program Files\Android\Android Studio\jbr',
  source: JdkSource.androidStudio,
  version: '21.0.3',
  vendor: 'JetBrains',
  arch: 'x86_64',
);

Widget _tile(
  Jdk jdk, {
  bool active = false,
  JdkTask? task,
  VoidCallback? onUse,
  VoidCallback? onJavaHome,
}) => JdkTile(
  jdk: jdk,
  isActiveForFlutter: active,
  task: task,
  onUseForFlutter: onUse ?? () {},
  onSetJavaHome: onJavaHome ?? () {},
  onShowInFolder: () {},
  onCopyPath: () {},
);

Widget _panel({
  ActiveJdk? active,
  bool configured = false,
  bool busy = false,
  VoidCallback? onSet,
}) => JavaIdentityPanel(
  active: active,
  configuredForFlutter: configured,
  busy: busy,
  onSetForFlutter: onSet ?? () {},
  onInstall: () {},
);

void main() {
  group('identity panel', () {
    testWidgets('offers to pin Flutter when nothing is configured',
        (tester) async {
      var sets = 0;
      await tester.pumpWidget(
        _host(
          _panel(
            active: const ActiveJdk(_adoptium, ActiveJdkSource.javaHome),
            onSet: () => sets++,
          ),
        ),
      );

      expect(find.text('JDK 17'), findsOneWidget);
      expect(find.text('JAVA_HOME'), findsOneWidget);
      expect(find.text('Set for Flutter'), findsOneWidget);
      expect(find.text('Flutter is using system default'), findsOneWidget);

      await tester.tap(find.text('Set for Flutter'));
      expect(sets, 1);
    });

    testWidgets('confirms quietly once flutter config names a JDK',
        (tester) async {
      await tester.pumpWidget(
        _host(
          _panel(
            active: const ActiveJdk(_adoptium, ActiveJdkSource.flutterConfig),
            configured: true,
          ),
        ),
      );

      expect(find.text('flutter config'), findsOneWidget);
      expect(find.text('Used by Flutter builds'), findsOneWidget);
      expect(find.text('Set for Flutter'), findsNothing);
    });

    testWidgets('an empty machine gets the install card', (tester) async {
      var installs = 0;
      await tester.pumpWidget(
        _host(
          JavaIdentityPanel(
            active: null,
            configuredForFlutter: false,
            busy: false,
            onSetForFlutter: () {},
            onInstall: () => installs++,
          ),
        ),
      );

      expect(find.text('No JDK detected'), findsOneWidget);
      await tester.tap(find.text('Install JDK'));
      expect(installs, 1);
    });
  });

  group('JDK tile', () {
    testWidgets('a usable JDK offers to take over Flutter builds',
        (tester) async {
      var uses = 0;
      await tester.pumpWidget(_host(_tile(_adoptium, onUse: () => uses++)));

      expect(find.text('JDK 17'), findsOneWidget);
      expect(find.text('Eclipse Adoptium'), findsOneWidget);
      expect(find.text('17.0.11'), findsOneWidget);
      expect(find.text('x86_64'), findsOneWidget);
      // Where it was found, so two JDKs of the same version stay apart.
      expect(find.text('registry'), findsOneWidget);

      await tester.tap(find.text('Use for Flutter'));
      expect(uses, 1);
    });

    testWidgets('the active tile has nothing to switch to', (tester) async {
      await tester.pumpWidget(_host(_tile(_jbr, active: true)));

      expect(find.text('active'), findsOneWidget);
      expect(find.text('Use for Flutter'), findsNothing);
      expect(find.text('Android Studio'), findsOneWidget);
    });

    testWidgets('an in-flight switch says so and takes no second click',
        (tester) async {
      var uses = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            _adoptium,
            task: JdkTask.settingFlutter,
            onUse: () => uses++,
          ),
        ),
      );

      expect(find.text('Setting…'), findsOneWidget);
      await tester.tap(find.text('Setting…'));
      expect(uses, 0);
    });

    testWidgets('a JRE is listed, reasoned and inert', (tester) async {
      await tester.pumpWidget(
        _host(
          _tile(
            const Jdk(
              path: r'C:\Program Files\Java\jre1.8.0_401',
              source: JdkSource.disk,
              version: '1.8.0_401',
              validity: JdkValidity.jreOnly,
            ),
          ),
        ),
      );

      expect(find.text('JDK 8'), findsOneWidget);
      expect(find.text('JRE only'), findsOneWidget);
      expect(find.text('Use for Flutter'), findsNothing);
      expect(find.byIcon(FluentIcons.more), findsNothing);
    });

    testWidgets('an unreadable JDK is listed with its reason', (tester) async {
      await tester.pumpWidget(
        _host(
          _tile(
            const Jdk(
              path: r'D:\broken\jdk',
              source: JdkSource.manual,
              validity: JdkValidity.invalid,
            ),
          ),
        ),
      );

      expect(find.text('JDK'), findsOneWidget);
      expect(find.text('invalid'), findsOneWidget);
      expect(find.text('manual'), findsOneWidget);
    });

    testWidgets('the kebab holds the environment and folder actions',
        (tester) async {
      var javaHomes = 0;
      await tester.pumpWidget(
        _host(_tile(_adoptium, onJavaHome: () => javaHomes++)),
      );
      await tester.tap(find.byIcon(FluentIcons.more));
      await tester.pumpAndSettle();

      expect(find.text('Show in folder'), findsOneWidget);
      expect(find.text('Copy path'), findsOneWidget);

      await tester.tap(find.text('Set as JAVA_HOME'));
      await tester.pumpAndSettle();
      expect(javaHomes, 1);
    });

    testWidgets('a narrow window ellipsizes rather than overflowing',
        (tester) async {
      for (final width in const [720.0, 560.0, 420.0, 360.0]) {
        await tester.pumpWidget(_host(_tile(_adoptium), width: width));
        expect(tester.takeException(), isNull, reason: 'at ${width}px');
      }
    });
  });

  group('java state', () {
    const jdks = [_adoptium, _jbr];

    test('the active JDK follows flutter config first', () {
      const state = JavaState(
        jdks: jdks,
        flutterJdkDir: r'C:\Program Files\Android\Android Studio\jbr',
        javaHome: r'C:\Program Files\Eclipse Adoptium\jdk-17.0.11-hotspot',
      );

      expect(state.active!.jdk, _jbr);
      expect(state.active!.source, ActiveJdkSource.flutterConfig);
      expect(state.configuredForFlutter, isTrue);
      expect(state.isActiveForFlutter(_jbr), isTrue);
      expect(state.isActiveForFlutter(_adoptium), isFalse);
    });

    test('no flutter setting means no tile is active for Flutter', () {
      const state = JavaState(
        jdks: jdks,
        javaHome: r'C:\Program Files\Eclipse Adoptium\jdk-17.0.11-hotspot',
      );

      expect(state.configuredForFlutter, isFalse);
      expect(state.isActiveForFlutter(_adoptium), isFalse);
      expect(state.active!.source, ActiveJdkSource.javaHome);
    });

    test('the count names how many and which one is in use', () {
      const none = JavaState(jdks: jdks);
      expect(none.countLabel, '2 JDKs');

      const one = JavaState(
        jdks: [_adoptium],
        javaHome: r'C:\Program Files\Eclipse Adoptium\jdk-17.0.11-hotspot',
      );
      expect(one.countLabel, '1 JDK · JDK 17 in use');
    });

    test('the compatibility hint only fires on a real conflict', () {
      const fine = JavaState(
        jdks: [_jbr],
        javaHome: r'C:\Program Files\Android\Android Studio\jbr',
        flutterVersion: '3.24.5',
      );
      expect(fine.compatibilityWarning, isNull);

      const conflict = JavaState(
        jdks: [
          Jdk(path: r'C:\jdk-24', source: JdkSource.disk, version: '24.0.1'),
        ],
        javaHome: r'C:\jdk-24',
        flutterVersion: '3.24.5',
      );
      expect(conflict.compatibilityWarning, contains('JDK 24'));
    });
  });
}
