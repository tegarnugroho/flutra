import 'package:android_sdk_manager/presentation/common/page_scaffold.dart';
import 'package:android_sdk_manager/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Windows is where the app runs, and it is the platform whose scroll behaviour
/// actually attaches a scrollbar.
void main() {
  /// Runs [body] as Windows. The override has to be cleared before the test
  /// function returns — the framework asserts on it before tearDown runs.
  Future<void> onWindows(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpPage(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(946, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FluentApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: PageScaffold(title: 'Settings', child: body),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the body fills the page even when its content is narrow',
    (tester) async => onWindows(() async {
      // A form capped well under the window width — the case that exposed the
      // bug: with a loose cross-axis the body shrank to its content and dragged
      // the scrollbar inward with it.
      await pumpPage(
        tester,
        SingleChildScrollView(
          padding: kPageBodyPadding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                for (var i = 0; i < 40; i++) const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      );

      final page = tester.getRect(find.byType(PageScaffold));
      expect(
        tester.getRect(find.byType(Scrollbar).first).right,
        page.right,
        reason: 'the scrollbar must sit on the window edge, not on the content',
      );
      expect(tester.getRect(find.byType(Scrollable).first).width, page.width);
    }),
  );

  testWidgets(
    'a full-width body is unaffected',
    (tester) async => onWindows(() async {
      await pumpPage(
        tester,
        ListView(
          padding: kPageBodyPadding,
          children: [for (var i = 0; i < 40; i++) const SizedBox(height: 40)],
        ),
      );

      expect(
        tester.getRect(find.byType(Scrollable).first).width,
        tester.getRect(find.byType(PageScaffold)).width,
      );
    }),
  );
}
