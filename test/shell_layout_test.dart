import 'package:android_sdk_manager/presentation/shell/custom_title_bar.dart';
import 'package:android_sdk_manager/presentation/theme/app_colors.dart';
import 'package:android_sdk_manager/presentation/theme/app_text_styles.dart';
import 'package:android_sdk_manager/presentation/theme/app_theme.dart';
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 4),
        child: Text(text, style: AppTextStyles.sectionLabel),
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
        leading: TitleBarActionButton(
          icon: FluentIcons.global_nav_button,
          tooltip: 'Toggle sidebar',
          onPressed: () {},
        ),
        actions: [
          TitleBarActionButton(
            icon: FluentIcons.search,
            tooltip: 'Go to page',
            onPressed: () {},
          ),
          const SizedBox(width: 6),
          TitleBarActionButton(
            icon: FluentIcons.back,
            tooltip: 'Back',
            onPressed: null,
          ),
          TitleBarActionButton(
            icon: FluentIcons.forward,
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
        indicator: null,
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
}
