import 'package:android_sdk_manager/presentation/common/app_loader.dart';
import 'package:android_sdk_manager/presentation/common/loading_switcher.dart';
import 'package:android_sdk_manager/presentation/common/skeleton/skeleton_layouts.dart';
import 'package:android_sdk_manager/presentation/common/skeleton/skeleton_primitives.dart';
import 'package:android_sdk_manager/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  ThemeMode mode = ThemeMode.dark,
  bool reducedMotion = false,
}) {
  return FluentApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: child!,
    ),
    home: ScaffoldPage(padding: EdgeInsets.zero, content: child),
  );
}

/// Every screen skeleton, with the width the real screen gets beside the pane.
const _skeletons = <String, Widget>{
  'dashboard': DashboardSkeleton(),
  'sdk manager': SdkManagerSkeleton(),
  'virtual devices': EmulatorListSkeleton(),
  'devices': DeviceListSkeleton(),
  'updates': UpdatesSkeleton(),
  'flutter sdk': FlutterSdkSkeleton(),
  'flutter doctor': DoctorSkeleton(),
  'logcat': LogcatSkeleton(),
  'settings addresses': AddressListSkeleton(),
};

void main() {
  group('AppLoader', () {
    testWidgets('animates and repaints while running', (tester) async {
      await tester.pumpWidget(_host(const Center(child: AppLoader())));
      await tester.pump();

      // A running loader keeps scheduling frames.
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('goes static when the OS disables animations', (tester) async {
      await tester.pumpWidget(
        _host(const Center(child: AppLoader()), reducedMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sizes itself per AppLoaderSize', (tester) async {
      for (final (size, side) in const [
        (AppLoaderSize.small, 16.0),
        (AppLoaderSize.medium, 28.0),
        (AppLoaderSize.large, 44.0),
      ]) {
        await tester.pumpWidget(_host(Center(child: AppLoader(size: size))));
        await tester.pump();
        expect(tester.getSize(find.byType(AppLoader)), Size(side, side));
      }
    });
  });

  group('SkeletonShimmer', () {
    testWidgets('runs one controller for the whole subtree', (tester) async {
      await tester.pumpWidget(
        _host(
          const SkeletonShimmer(
            child: Column(
              children: [
                SkeletonLine(width: 100),
                SkeletonBox(width: 60, height: 20),
                SkeletonCircle(size: 16),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Each shape masks itself, so real chrome can sit between them without
      // being recoloured — but they all read the same animation, which is what
      // "one controller" has to mean now. Counting ShaderMasks would only
      // count shapes.
      expect(find.byType(ShaderMask), findsNWidgets(3));
      expect(tester.binding.transientCallbackCount, 1);

      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 1);
    });

    testWidgets('a nested shimmer does not start a second controller',
        (tester) async {
      // A page skeleton may reuse a component's skeleton, and that component
      // wraps itself so it still shimmers when used on its own.
      await tester.pumpWidget(
        _host(
          const SkeletonShimmer(
            child: Column(
              children: [
                SkeletonLine(width: 100),
                SkeletonShimmer(child: SkeletonBox(width: 60, height: 20)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.binding.transientCallbackCount, 1);
    });

    testWidgets('drops the sweep when animations are disabled', (tester) async {
      await tester.pumpWidget(
        _host(
          const SkeletonShimmer(child: SkeletonLine(width: 100)),
          reducedMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('LoadingSwitcher', () {
    Widget build(bool showSkeleton) => _host(
          LoadingSwitcher(
            showSkeleton: showSkeleton,
            skeleton: const Text('skeleton'),
            builder: (context) => const Text('content'),
          ),
        );

    testWidgets('never shows a skeleton when data is already there',
        (tester) async {
      await tester.pumpWidget(build(false));
      await tester.pump();

      expect(find.text('content'), findsOneWidget);
      expect(find.text('skeleton'), findsNothing);
    });

    testWidgets('holds the skeleton for the minimum display time',
        (tester) async {
      await tester.pumpWidget(build(true));
      await tester.pump();
      expect(find.text('skeleton'), findsOneWidget);

      // Data lands after 40ms — far too fast to show a placeholder honestly.
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(find.text('skeleton'), findsOneWidget);
      expect(find.text('content'), findsNothing);

      // Still held just before 300ms.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('content'), findsNothing);

      // Released after, then cross-faded in.
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('content'), findsOneWidget);
      expect(find.text('skeleton'), findsNothing);
    });

    testWidgets('anchors both children to the top, not the centre',
        (tester) async {
      // A page body that shrink-wraps is the trap: the default AnimatedSwitcher
      // layout centres it, leaving the content floating mid-window.
      Widget page(bool showSkeleton) => _host(
            LoadingSwitcher(
              showSkeleton: showSkeleton,
              skeleton: const SingleChildScrollView(
                child: SizedBox(height: 40, key: ValueKey('skeleton-body')),
              ),
              builder: (context) => const SingleChildScrollView(
                child: SizedBox(height: 40, key: ValueKey('content-body')),
              ),
            ),
          );

      await tester.pumpWidget(page(true));
      await tester.pump();
      final top = tester.getTopLeft(find.byType(LoadingSwitcher)).dy;
      expect(tester.getTopLeft(find.byKey(const ValueKey('skeleton-body'))).dy,
          top);

      await tester.pump(kSkeletonMinDisplay);
      await tester.pumpWidget(page(false));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(const ValueKey('content-body'))).dy,
          top);
    });

    testWidgets('swaps immediately once the minimum has already elapsed',
        (tester) async {
      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 900));

      await tester.pumpWidget(build(false));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('content'), findsOneWidget);
      expect(find.text('skeleton'), findsNothing);
    });
  });

  group('screen skeletons', () {
    // Content width beside the open (190) and compact (52) navigation pane, at
    // the narrowest and a roomy window.
    const widths = <double>[770, 908, 1410];

    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      for (final entry in _skeletons.entries) {
        for (final width in widths) {
          testWidgets(
            '${entry.key} lays out at ${width}px, ${mode.name}',
            (tester) async {
              tester.view.physicalSize = Size(width, 820);
              tester.view.devicePixelRatio = 1.0;
              addTearDown(tester.view.reset);

              await tester.pumpWidget(_host(entry.value, mode: mode));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));

              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });
}
