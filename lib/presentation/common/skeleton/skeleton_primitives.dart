import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../loading_switcher.dart';

/// The opaque fill a skeleton shape rests at.
///
/// Blended against the scaffold background rather than left translucent: the
/// shimmer masks by alpha, and a 5%-alpha shape would let through only 5% of
/// the sweep.
Color skeletonFill(BuildContext context) {
  final theme = FluentTheme.of(context);
  return Color.alphaBlend(
    AppColors.skeletonBase(theme.brightness),
    theme.scaffoldBackgroundColor,
  );
}

/// The brighter band swept across [skeletonFill].
Color skeletonHighlightFill(BuildContext context) {
  final theme = FluentTheme.of(context);
  return Color.alphaBlend(
    AppColors.skeletonHighlight(theme.brightness),
    theme.scaffoldBackgroundColor,
  );
}

/// A rounded rectangle standing in for a block of content.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ShimmerShape(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: skeletonFill(context),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// A stand-in for one line of text. Pass no [width] to fill the available room.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.width, this.height = 12});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final line = SkeletonBox(width: width, height: height, radius: height / 2);
    return width == null
        ? line
        : Align(alignment: Alignment.centerLeft, child: line);
  }
}

/// A stand-in for an icon or status dot.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShimmerShape(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: skeletonFill(context),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Owns the one animation every skeleton shape below it paints from.
///
/// Wrap a screen skeleton in exactly one of these. The shapes mask themselves
/// rather than being masked as a group, which is what lets a skeleton mix
/// placeholders with the real chrome around them — a card's border, its static
/// label, a divider — instead of turning the whole card into a grey slab.
///
/// The band is still positioned in *this* widget's coordinates, so it reads as
/// one sweep travelling across the page rather than each shape flashing on its
/// own.
///
/// Renders the flat base colour, with no sweep, when the OS has animations off.
///
// TODO(raster): each shape now costs its own small saveLayer instead of one
// page-sized one. Which is cheaper is a raster-thread question that needs a
// profile-mode DevTools capture; the UI-thread stall that was actually measured
// came from process spawning, not from either shape of this.
// TODO(pacing): if stutter survives with a clean timeline, check 144Hz vsync
// pacing on Windows rather than tuning the 1400ms duration to hide it.
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Nesting is a no-op rather than a second controller: a page skeleton may
    // reuse a component's own skeleton, and each wraps itself so it still
    // shimmers when used alone.
    if (ShimmerScope.of(context) != null) return child;
    return _ShimmerHost(child: child);
  }
}

class _ShimmerHost extends StatefulWidget {
  const _ShimmerHost({required this.child});

  final Widget child;

  @override
  State<_ShimmerHost> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<_ShimmerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// Identifies the scope's box, so a shape can work out where it sits in it.
  final GlobalKey _scopeKey = GlobalKey();

  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    // The switcher keeps this subtree mounted through the cross-fade to the
    // real content. Sweeping over it during those frames buys nothing and
    // competes with the content's first layout, so the ticker stops the moment
    // the swap starts.
    final visible = SkeletonVisibility.of(context);
    if (_reducedMotion || !visible) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ShimmerScope(
        key: _scopeKey,
        controller: _controller,
        scopeKey: _scopeKey,
        base: skeletonFill(context),
        highlight: skeletonHighlightFill(context),
        animate: !_reducedMotion,
        child: widget.child,
      ),
    );
  }
}

/// The shared animation and colours, handed down to every shape.
class ShimmerScope extends InheritedWidget {
  const ShimmerScope({
    super.key,
    required this.controller,
    required this.scopeKey,
    required this.base,
    required this.highlight,
    required this.animate,
    required super.child,
  });

  /// Drives every shape below. One controller, however many shapes there are.
  final Animation<double> controller;

  /// The scope's own key, used to measure where a shape sits inside it.
  final GlobalKey scopeKey;

  final Color base;
  final Color highlight;

  /// False when the OS asks for no animation — shapes then paint flat.
  final bool animate;

  static ShimmerScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShimmerScope>();

  /// The gradient slice that falls on the shape built at [shapeContext].
  ///
  /// Built over the scope's rectangle and shifted by the shape's offset inside
  /// it, so neighbouring shapes show consecutive parts of one band. Before
  /// layout has run there is nothing to measure, and the shape falls back to
  /// sweeping its own bounds for that first frame.
  Shader shaderFor(BuildContext shapeContext, Rect bounds, double t) {
    var origin = Offset.zero;
    var area = bounds.size;

    final scopeBox = scopeKey.currentContext?.findRenderObject();
    final shapeBox = shapeContext.findRenderObject();
    if (scopeBox is RenderBox &&
        shapeBox is RenderBox &&
        scopeBox.hasSize &&
        shapeBox.hasSize &&
        scopeBox.attached &&
        shapeBox.attached) {
      origin = scopeBox.globalToLocal(shapeBox.localToGlobal(Offset.zero));
      area = scopeBox.size;
    }

    return LinearGradient(
      begin: const Alignment(-1, -0.6),
      end: const Alignment(1, 0.6),
      colors: [base, highlight, base],
      stops: const [0.35, 0.5, 0.65],
      transform: _SweepTransform(t),
    ).createShader(
      Rect.fromLTWH(-origin.dx, -origin.dy, area.width, area.height),
    );
  }

  @override
  bool updateShouldNotify(ShimmerScope old) =>
      controller != old.controller ||
      base != old.base ||
      highlight != old.highlight ||
      animate != old.animate;
}

/// Paints [child] with the scope's travelling band.
///
/// Public so a screen can shimmer a shape of its own — a chart bar, a chip —
/// without that shape having to be one of the primitives above. Outside a
/// [SkeletonShimmer] it renders the child untouched, so a placeholder used on
/// its own still looks like a placeholder.
class ShimmerShape extends StatelessWidget {
  const ShimmerShape({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = ShimmerScope.of(context);
    if (scope == null || !scope.animate) return child;

    return AnimatedBuilder(
      animation: scope.controller,
      builder: (context, child) => ShaderMask(
        // srcIn keeps the shape's silhouette and takes its colour entirely
        // from the gradient, which is why the shapes are opaque.
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) =>
            scope.shaderFor(context, bounds, scope.controller.value),
        child: child,
      ),
      child: child,
    );
  }
}

/// Slides the gradient from fully before the subtree to fully past it.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.t);

  /// 0..1 through the sweep.
  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    // -1.5 → 1.5 of the scope width, so the band is off-screen at both ends.
    return Matrix4.translationValues(bounds.width * (t * 3 - 1.5), 0, 0);
  }
}
