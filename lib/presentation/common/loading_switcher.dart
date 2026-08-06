import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

/// How long a skeleton stays up once shown, so a fast load doesn't flash it.
const kSkeletonMinDisplay = Duration(milliseconds: 300);

/// How long the skeleton takes to fade into the real content.
const kSkeletonFade = Duration(milliseconds: 200);

/// Swaps a screen's skeleton for its content once the data lands.
///
/// Two rules the screens would otherwise each reinvent:
///
///  * a skeleton that goes up stays up for [kSkeletonMinDisplay], so a load
///    that finishes in 40ms doesn't flash a one-frame placeholder;
///  * the swap is a [kSkeletonFade] cross-fade, never a hard cut.
///
/// Data that is already cached on the first build never shows a skeleton at
/// all — [showSkeleton] is false from the start and nothing is held.
class LoadingSwitcher extends StatefulWidget {
  const LoadingSwitcher({
    super.key,
    required this.showSkeleton,
    required this.skeleton,
    required this.builder,
  });

  /// True while the screen has no data to show yet.
  final bool showSkeleton;

  final Widget skeleton;

  /// Builds the real content. Only called once [showSkeleton] is false, so it
  /// may assume the data is there.
  final WidgetBuilder builder;

  @override
  State<LoadingSwitcher> createState() => _LoadingSwitcherState();
}

class _LoadingSwitcherState extends State<LoadingSwitcher> {
  final _shown = Stopwatch();
  Timer? _hold;

  late bool _showing = widget.showSkeleton;

  @override
  void initState() {
    super.initState();
    if (_showing) _shown.start();
  }

  @override
  void didUpdateWidget(covariant LoadingSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.showSkeleton == old.showSkeleton) return;

    if (widget.showSkeleton) {
      _hold?.cancel();
      _shown
        ..reset()
        ..start();
      setState(() => _showing = true);
      return;
    }

    final remaining = kSkeletonMinDisplay - _shown.elapsed;
    _shown.stop();
    if (remaining <= Duration.zero) {
      setState(() => _showing = false);
    } else {
      _hold?.cancel();
      _hold = Timer(remaining, () {
        if (mounted) setState(() => _showing = false);
      });
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SkeletonVisibility(
      showing: _showing,
      child: _switcher(context),
    );
  }

  Widget _switcher(BuildContext context) {
    return AnimatedSwitcher(
      duration: kSkeletonFade,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      // The default layout centres its children in a loosely-fitted Stack,
      // which makes a shrink-wrapping page body (a SingleChildScrollView)
      // float in the middle of the window. Page bodies fill from the top.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: [...previousChildren, ?currentChild],
      ),
      child: _showing
          ? KeyedSubtree(
              key: const ValueKey('skeleton'),
              child: widget.skeleton,
            )
          : KeyedSubtree(
              key: const ValueKey('content'),
              child: widget.builder(context),
            ),
    );
  }
}

/// Tells the skeleton subtree whether it is still the thing being shown.
///
/// Sits *above* the [AnimatedSwitcher] on purpose. The switcher keeps the
/// outgoing skeleton mounted for the whole [kSkeletonFade], and never rebuilds
/// it — so a flag passed down through the child would stay stale and the
/// shimmer would keep ticking (and repainting a full-page ShaderMask) while the
/// real content is doing its first layout. An inherited widget above the
/// switcher still notifies that retained subtree, which is what stops it.
class SkeletonVisibility extends InheritedWidget {
  const SkeletonVisibility({
    super.key,
    required this.showing,
    required super.child,
  });

  /// False once the swap to real content has begun.
  final bool showing;

  /// Defaults to true, so a skeleton used outside a [LoadingSwitcher] animates.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SkeletonVisibility>()
          ?.showing ??
      true;

  @override
  bool updateShouldNotify(SkeletonVisibility old) => showing != old.showing;
}
