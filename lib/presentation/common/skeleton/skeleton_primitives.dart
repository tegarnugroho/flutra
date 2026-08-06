import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../loading_switcher.dart';

/// The opaque fill a skeleton shape rests at.
///
/// Blended against the scaffold background rather than left translucent: the
/// shimmer in [SkeletonShimmer] masks by alpha, and a 5%-alpha shape would let
/// through only 5% of the sweep.
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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: skeletonFill(context),
        borderRadius: BorderRadius.circular(radius),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: skeletonFill(context),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Sweeps a highlight band diagonally across [child].
///
/// Wrap a whole screen skeleton in exactly one of these: a single controller
/// drives every shape, so they shimmer in sync and cost one animation.
///
/// The mask recolours everything it covers, so the subtree must contain only
/// skeleton primitives and spacing — no real text or icons.
///
/// Renders the flat base colour, with no sweep, when the OS has animations off.
///
// TODO(raster): the sweep costs a full-page saveLayer every frame, because
// ShaderMask rebuilds its gradient shader on each tick. That is raster-thread
// cost, which cannot be measured from a headless test — it needs a profile-mode
// DevTools capture. If a capture shows raster time elevated while the skeleton
// is up, the swap is to a pulse-opacity skeleton (one FadeTransition over flat
// boxes, same block sizes). Not done on suspicion: the UI-thread stall that was
// actually measured came from process spawning, not from this.
// TODO(pacing): if stutter survives with a clean timeline, check 144Hz vsync
// pacing on Windows rather than tuning the 1400ms duration to hide it.
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    // The switcher keeps this subtree mounted through the cross-fade to the
    // real content. Sweeping a full-page ShaderMask over it during those frames
    // buys nothing and competes with the content's first layout, so the ticker
    // stops the moment the swap starts.
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
    if (_reducedMotion) return widget.child;

    final base = skeletonFill(context);
    final highlight = skeletonHighlightFill(context);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => ShaderMask(
          // srcIn keeps each shape's silhouette and takes its colour entirely
          // from the gradient, which is why the shapes must be opaque.
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: const Alignment(-1, -0.6),
            end: const Alignment(1, 0.6),
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
            transform: _SweepTransform(_controller.value),
          ).createShader(bounds),
          child: child,
        ),
        child: widget.child,
      ),
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
    // -1.5 → 1.5 of the subtree width, so the band is off-screen at both ends.
    return Matrix4.translationValues(bounds.width * (t * 3 - 1.5), 0, 0);
  }
}
