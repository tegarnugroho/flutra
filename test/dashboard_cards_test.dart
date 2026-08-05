import 'package:android_sdk_manager/presentation/dashboard/widgets/stat_cards.dart';
import 'package:android_sdk_manager/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cards live in a fixed-extent grid, so their content has to fit the
/// height the grid hands them — a guess here clipped the sub-line by 12px.
Widget _host(Widget child, {double width = 904, ThemeMode mode = ThemeMode.dark}) {
  return FluentApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    home: ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: Column(mainAxisSize: MainAxisSize.min, children: [child]),
        ),
      ),
    ),
  );
}

void main() {
  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('a stat card fits its grid height, ${mode.name}',
        (tester) async {
      await tester.pumpWidget(
        _host(
          mode: mode,
          SizedBox(
            height: kStatCardHeight,
            width: 220,
            child: StatCard(
              label: 'Disk used',
              value: '42.7 GB',
              subtitle: '6.1 GB reclaimable',
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a quick action fits its grid height, ${mode.name}',
        (tester) async {
      await tester.pumpWidget(
        _host(
          mode: mode,
          SizedBox(
            height: kQuickActionHeight,
            width: 280,
            child: QuickAction(
              icon: FluentIcons.play,
              title: 'Launch Pixel 8',
              subtitle: 'last used AVD',
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the skeleton uses the same height as the real cards',
      (tester) async {
    await tester.pumpWidget(_host(const StatCardsSkeleton()));
    await tester.pump();

    final boxes = find.byType(GridView);
    expect(boxes, findsOneWidget);
    final delegate = (tester.widget<GridView>(boxes).gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount);
    expect(delegate.mainAxisExtent, kStatCardHeight);
    expect(tester.takeException(), isNull);
  });
}
