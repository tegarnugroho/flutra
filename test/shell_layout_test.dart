import 'package:flutra/presentation/shell/custom_title_bar.dart';
import 'package:flutra/presentation/theme/app_colors.dart';
import 'package:flutra/presentation/theme/app_text_styles.dart';
import 'package:flutra/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout regression test for the shell chrome.
///
/// The real [AppShell] can't be pumped — its selected page shells out to the
/// Android tools on build — so the pane is mirrored here. Keep this list in
/// step with `_AppShellState._destinations`.
const _labels = <(String, String?)>[
  ('Dashboard', null),
  ('SDK manager', 'Android'),
  ('Virtual devices', null),
  ('Licenses', null),
  ('Logcat', null),
  ('Updates', null),
  ('Flutter SDK', 'Flutter'),
  ('Flutter doctor', null),
  ('Devices', null),
];

PaneItem _item(String label) => PaneItem(
      icon: const Icon(FluentIcons.view_dashboard, size: 15),
      title: Text(label),
      selectedTileColor: WidgetStateProperty.all(AppColors.surfaceRaised),
      body: const SizedBox.shrink(),
    );

PaneItemWidgetAdapter _sectionLabel(String text) => PaneItemWidgetAdapter(
      applyPadding: false,
      child: Builder(
        builder: (context) {
          final rail = NavigationView.dataOf(context).displayMode ==
              PaneDisplayMode.compact;
          // Mirrors the shell: 52px of rail cannot hold a section caption.
          if (rail) {
            return Container(
              height: 24,
              alignment: Alignment.center,
              child: Container(
                height: AppShape.hairline,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: AppColors.border,
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 4),
            child: Text(text, style: AppTextStyles.of(context).sectionLabel),
          );
        },
      ),
    );

Widget _shell({required bool collapsed, ThemeMode mode = ThemeMode.dark}) {
  final items = <NavigationPaneItem>[];
  for (final (label, group) in _labels) {
    if (group != null) items.add(_sectionLabel(group));
    items.add(_item(label));
  }

  return FluentApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    home: NavigationView(
      titleBar: CustomTitleBar(
        leading: FlyoutTarget(
          controller: FlyoutController(),
          child: TitleBarActionButton(
            icon: WindowsIcons.global_nav_button,
            tooltip: 'Menu',
            onPressed: () {},
          ),
        ),
        actions: [
          TitleBarActionButton(
            icon: WindowsIcons.dock_left,
            tooltip: 'Hide sidebar',
            isActive: collapsed,
            onPressed: () {},
          ),
          TitleBarActionButton(
            icon: WindowsIcons.search,
            tooltip: 'Go to page',
            onPressed: () {},
          ),
          const SizedBox(width: 6),
          TitleBarActionButton(
            icon: WindowsIcons.back,
            tooltip: 'Back',
            onPressed: null,
          ),
          TitleBarActionButton(
            icon: WindowsIcons.forward,
            tooltip: 'Forward',
            onPressed: null,
          ),
        ],
      ),
      contentShape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border, width: AppShape.hairline),
      ),
      pane: NavigationPane(
        selected: 0,
        onChanged: (_) {},
        displayMode:
            collapsed ? PaneDisplayMode.compact : PaneDisplayMode.auto,
        size: const NavigationPaneSize(openWidth: 190, compactWidth: 52),
        indicator: const StickyNavigationIndicator(
          color: AppColors.accent,
          indicatorSize: 2.5,
        ),
        items: items,
        footerItems: [
          PaneItemSeparator(
            color: AppColors.border,
            thickness: AppShape.hairline,
          ),
          _item('Settings'),
        ],
      ),
    ),
  );
}

void main() {
  // The window can't go below 960x640, so anything narrower is out of scope.
  // Fractional device pixel ratios are the Windows norm (125% / 150% display
  // scaling) and give the shell fractional logical widths to lay out in.
  const widths = <double>[
    960,
    // Windows reports fractional logical widths under display scaling; the
    // sub-pixel remainder is where hairline layouts tip over.
    960.8,
    1000.4,
    1007.2,
    1008,
    1008.6,
    1136,
    1136.6,
    1366.4,
    1600,
    1920.8,
  ];
  const ratios = <double>[1.0, 1.25, 1.5, 1.75];

  // Toggling the sidebar swaps the pane between compact and open, and the pane
  // animates its width across the swap — narrow intermediate frames are where a
  // pane item's fixed icon padding can outgrow the row.
  testWidgets('collapsing and expanding the sidebar never overflows',
      (tester) async {
    tester.view.physicalSize = const Size(1136, 893);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shell(collapsed: false));
    await tester.pumpAndSettle();

    for (final collapsed in [true, false, true, false]) {
      await tester.pumpWidget(_shell(collapsed: collapsed));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        expect(
          tester.takeException(),
          isNull,
          reason: 'frame $frame while collapsed=$collapsed',
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    for (final collapsed in [false, true]) {
      for (final ratio in ratios) {
        for (final width in widths) {
          testWidgets(
            'shell lays out without overflow at ${width}x900 @${ratio}x, '
            'collapsed=$collapsed, ${mode.name}',
            (tester) async {
              tester.view.physicalSize = Size(width * ratio, 900 * ratio);
              tester.view.devicePixelRatio = ratio;
              addTearDown(tester.view.reset);

              await tester.pumpWidget(_shell(collapsed: collapsed, mode: mode));
              await tester.pumpAndSettle();

              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }

  group('rail mode', () {
    testWidgets('never renders section captions on the rail', (tester) async {
      tester.view.physicalSize = const Size(1136, 893);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(collapsed: false));
      await tester.pumpAndSettle();
      // Open pane: the captions are the group headings.
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('Flutter'), findsOneWidget);

      await tester.pumpWidget(_shell(collapsed: true));
      await tester.pumpAndSettle();
      // Rail: a caption here is the "Andr oid" wrap this mode exists to avoid.
      expect(find.text('Android'), findsNothing);
      expect(find.text('Flutter'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps item labels off the rail too', (tester) async {
      tester.view.physicalSize = const Size(1136, 893);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(collapsed: true));
      await tester.pumpAndSettle();

      // fluent lays compact items out icon-only; any visible label would be
      // wrapping in 52px.
      for (final label in ['SDK manager', 'Virtual devices', 'Settings']) {
        expect(
          find.text(label),
          findsNothing,
          reason: '"$label" should be a tooltip on the rail, not a label',
        );
      }
    });

    testWidgets('the swap does not reflow text at intermediate widths',
        (tester) async {
      tester.view.physicalSize = const Size(1136, 893);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell(collapsed: false));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_shell(collapsed: true));
      // Walk the whole 180ms tween: no caption may appear at any frame, and
      // nothing may overflow while the pane narrows.
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        expect(find.text('Android'), findsNothing, reason: 'frame $frame');
        expect(tester.takeException(), isNull, reason: 'frame $frame');
      }
    });
  });
}
