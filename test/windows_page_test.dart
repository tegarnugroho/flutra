import 'package:flutra/domain/entities/windows_toolchain.dart';
import 'package:flutra/presentation/theme/app_theme.dart';
import 'package:flutra/presentation/windows/widgets/requirement_tile.dart';
import 'package:flutra/presentation/windows/widgets/windows_identity_panel.dart';
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

const _install = VisualStudioInstall(
  displayName: 'Visual Studio Build Tools 2022',
  version: '17.14.37516.0',
  installPath: r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools',
  productId: kBuildToolsProductId,
  hasCppTools: true,
);

const _sdk = WindowsSdk(version: '10.0.26100.0', path: r'C:\Kits');

WindowsToolchain _toolchain({
  List<VisualStudioInstall> installs = const [_install],
  List<WindowsSdk> sdks = const [_sdk],
  DeveloperModeState developerMode = DeveloperModeState.on,
  bool? windowsDesktop = true,
}) => WindowsToolchain(
  installs: installs,
  sdks: sdks,
  developerMode: developerMode,
  windowsDesktopEnabled: windowsDesktop,
);

void main() {
  group('identity panel', () {
    testWidgets('a healthy machine confirms quietly, with no button',
        (tester) async {
      await tester.pumpWidget(
        _host(
          WindowsIdentityPanel(
            toolchain: _toolchain(),
            busy: false,
            onInstall: () {},
            onFixIssues: () {},
          ),
        ),
      );

      expect(find.text('Windows toolchain ready'), findsOneWidget);
      expect(find.text('Windows builds can run'), findsOneWidget);
      expect(find.text('Fix issues'), findsNothing);
      expect(find.text('Install Build Tools'), findsNothing);
    });

    testWidgets('an empty machine offers the bootstrapper', (tester) async {
      var installs = 0;
      await tester.pumpWidget(
        _host(
          WindowsIdentityPanel(
            toolchain: _toolchain(installs: const [], sdks: const []),
            busy: false,
            onInstall: () => installs++,
            onFixIssues: () {},
          ),
        ),
      );

      expect(find.text('Build tools not installed'), findsOneWidget);
      // The surprise worth pre-empting.
      expect(find.text('Windows will ask for permission'), findsOneWidget);

      await tester.tap(find.text('Install Build Tools'));
      expect(installs, 1);
    });

    testWidgets('issues are counted and lead to the first one', (tester) async {
      var fixes = 0;
      await tester.pumpWidget(
        _host(
          WindowsIdentityPanel(
            toolchain: _toolchain(
              sdks: const [],
              developerMode: DeveloperModeState.off,
            ),
            busy: false,
            onInstall: () {},
            onFixIssues: () => fixes++,
          ),
        ),
      );

      expect(find.text('2 issues blocking Windows builds'), findsOneWidget);
      await tester.tap(find.text('Fix issues'));
      expect(fixes, 1);
    });

    testWidgets('one issue is not "1 issues"', (tester) async {
      await tester.pumpWidget(
        _host(
          WindowsIdentityPanel(
            toolchain: _toolchain(windowsDesktop: false),
            busy: false,
            onInstall: () {},
            onFixIssues: () {},
          ),
        ),
      );

      expect(find.text('1 issue blocking Windows builds'), findsOneWidget);
    });

    testWidgets('a running installer disables the button', (tester) async {
      var fixes = 0;
      await tester.pumpWidget(
        _host(
          WindowsIdentityPanel(
            toolchain: _toolchain(windowsDesktop: false),
            busy: true,
            onInstall: () {},
            onFixIssues: () => fixes++,
          ),
        ),
      );

      await tester.tap(find.text('Fix issues'));
      expect(fixes, 0);
    });
  });

  group('requirement tile', () {
    WindowsRequirement requirementOf(
      WindowsToolchain toolchain,
      WindowsRequirementKind kind,
    ) => toolchain.requirements.firstWhere((r) => r.kind == kind);

    testWidgets('a satisfied requirement carries no button', (tester) async {
      await tester.pumpWidget(
        _host(
          RequirementTile(
            requirement: requirementOf(
              _toolchain(),
              WindowsRequirementKind.cppToolchain,
            ),
            busy: false,
            pending: false,
            onAction: () {},
          ),
        ),
      );

      expect(find.text('Visual Studio C++ toolchain'), findsOneWidget);
      expect(find.byIcon(FluentIcons.check_mark), findsOneWidget);
      expect(find.byType(Button), findsNothing);
    });

    testWidgets('a problem names its one action', (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        _host(
          RequirementTile(
            requirement: requirementOf(
              _toolchain(developerMode: DeveloperModeState.off),
              WindowsRequirementKind.developerMode,
            ),
            busy: false,
            pending: false,
            onAction: () => actions++,
          ),
        ),
      );

      expect(find.byIcon(FluentIcons.warning), findsOneWidget);
      expect(find.text('Enable Developer Mode, then return and refresh.'),
          findsOneWidget);

      await tester.tap(find.text('Open settings'));
      expect(actions, 1);
    });

    testWidgets('an in-flight action says so and takes no second click',
        (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        _host(
          RequirementTile(
            requirement: requirementOf(
              _toolchain(windowsDesktop: false),
              WindowsRequirementKind.flutterConfig,
            ),
            busy: true,
            pending: true,
            onAction: () => actions++,
          ),
        ),
      );

      expect(find.text('Working…'), findsOneWidget);
      await tester.tap(find.text('Working…'));
      expect(actions, 0);
    });

    testWidgets('another operation disables this one too', (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        _host(
          RequirementTile(
            requirement: requirementOf(
              _toolchain(sdks: const []),
              WindowsRequirementKind.windowsSdk,
            ),
            // Busy because a different tile's installer is running.
            busy: true,
            pending: false,
            onAction: () => actions++,
          ),
        ),
      );

      await tester.tap(find.text('Install via VS Installer'));
      expect(actions, 0);
    });

    testWidgets('the install path rides under the detail line', (tester) async {
      await tester.pumpWidget(
        _host(
          RequirementTile(
            requirement: requirementOf(
              _toolchain(),
              WindowsRequirementKind.cppToolchain,
            ),
            busy: false,
            pending: false,
            onAction: () {},
            trailingPath: _install.installPath,
          ),
        ),
      );

      expect(find.text(_install.installPath), findsOneWidget);
    });

    testWidgets('a narrow window ellipsizes rather than overflowing',
        (tester) async {
      for (final width in const [720.0, 560.0, 420.0, 360.0]) {
        await tester.pumpWidget(
          _host(
            RequirementTile(
              requirement: requirementOf(
                _toolchain(installs: const [], sdks: const []),
                WindowsRequirementKind.cppToolchain,
              ),
              busy: false,
              pending: false,
              onAction: () {},
              trailingPath: _install.installPath,
            ),
            width: width,
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at ${width}px');
      }
    });
  });
}
