import 'package:flutra/presentation/common/loading_switcher.dart';
import 'package:flutra/presentation/common/skeleton/skeleton_layouts.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Number of animations currently driving frames. One shimmer sweep is one.
int activeTickers(WidgetTester tester) =>
    tester.binding.transientCallbackCount;

Widget _host({required bool showSkeleton}) => FluentApp(
      home: ScaffoldPage(
        content: LoadingSwitcher(
          showSkeleton: showSkeleton,
          skeleton: const DashboardSkeleton(),
          builder: (_) => const Text('content'),
        ),
      ),
    );

void main() {
  group('dashboard skeleton shimmer', () {
    setUp(() {
      // The dashboard skeleton is a full window's worth of blocks; the default
      // 800x600 test surface overflows it.
      final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
      view.physicalSize = const Size(1280, 900);
      view.devicePixelRatio = 1.0;
    });

    tearDown(() {
      final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('the whole skeleton runs on exactly one ticker',
        (tester) async {
      await tester.pumpWidget(_host(showSkeleton: true));
      // Settle the page's own entrance animations first; what is left running
      // is the shimmer.
      await tester.pump(const Duration(seconds: 1));

      // ~15 placeholder blocks, one sweep driving all of them.
      expect(find.byType(DashboardSkeleton), findsOneWidget);
      expect(activeTickers(tester), 1);

      await tester.pumpWidget(_host(showSkeleton: false));
      await tester.pumpAndSettle();
    });

    testWidgets('the ticker stops as soon as the swap to content begins',
        (tester) async {
      /// Swaps [skeleton] out for real content and reports how many animations
      /// are running mid-cross-fade.
      Future<int> tickersDuringSwap(Widget skeleton) async {
        Widget host(bool showSkeleton) => FluentApp(
              home: ScaffoldPage(
                content: LoadingSwitcher(
                  showSkeleton: showSkeleton,
                  skeleton: skeleton,
                  builder: (_) => const Text('content'),
                ),
              ),
            );

        await tester.pumpWidget(host(true));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(host(false));
        // The skeleton is held for a minimum display time before it may go —
        // by a real Timer, so the clock has to reach it before the swap starts.
        await tester.pump(kSkeletonMinDisplay);
        await tester.pump(const Duration(milliseconds: 50));
        final mid = activeTickers(tester);
        await tester.pumpAndSettle();
        return mid;
      }

      // The switcher runs its own cross-fade animations; that count is the
      // floor, and it is what a skeleton with no shimmer costs.
      final fadeOnly = await tickersDuringSwap(const SizedBox.expand());
      final withShimmer = await tickersDuringSwap(const DashboardSkeleton());

      // The shimmer must add nothing while it is being faded out, even though
      // the skeleton is still mounted for those frames. Comparing against the
      // floor rather than a hard number keeps this honest if the switcher's own
      // animation count ever changes.
      expect(withShimmer, fadeOnly);

      // Criterion 5: nothing left ticking behind the real content.
      expect(find.byType(DashboardSkeleton), findsNothing);
      expect(find.text('content'), findsOneWidget);
      expect(activeTickers(tester), 0);
    });

    testWidgets('no ticker at all when the OS has animations off',
        (tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const ScaffoldPage(content: DashboardSkeleton()),
          ),
        ),
      );
      await tester.pump();
      expect(activeTickers(tester), 0);
    });
  });
}
