import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';

/// The three sizes the app draws [AppLoader] at.
enum AppLoaderSize {
  /// 16px — inline, inside buttons and list rows.
  small,

  /// 28px — cards and sections.
  medium,

  /// 44px — full-page fallback where no skeleton fits.
  large,
}

extension on AppLoaderSize {
  double get dimension => switch (this) {
        AppLoaderSize.small => 16,
        AppLoaderSize.medium => 28,
        AppLoaderSize.large => 44,
      };

  double get stroke => switch (this) {
        AppLoaderSize.small => 2,
        AppLoaderSize.medium => 3,
        AppLoaderSize.large => 4,
      };
}

/// The app's indeterminate loader: three rounded arcs chasing each other
/// around a shared centre at slightly different speeds.
///
/// Use it for waits with no measurable progress. For an initial page load
/// prefer a skeleton — the layout appearing instantly reads as faster.
///
/// When the OS has animations turned off the loader draws a static arc.
class AppLoader extends StatefulWidget {
  const AppLoader({super.key, this.size = AppLoaderSize.medium, this.color});

  final AppLoaderSize size;

  /// Colour of the leading arc.
  ///
  /// Defaults to a neutral text tone rather than [AppColors.accent]: the accent
  /// is reserved for the channel chip on the Flutter SDK screen and spending it
  /// on every spinner would tint the whole app.
  final Color? color;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
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
    final palette = AppPalette.of(context);
    final leading = widget.color ?? palette.textTertiary;
    final trailing = palette.textMuted.withValues(alpha: 0.35);
    final side = widget.size.dimension;

    return RepaintBoundary(
      child: SizedBox(
        width: side,
        height: side,
        child: _reducedMotion
            ? CustomPaint(
                painter: _RingPainter(
                  progress: 0,
                  stroke: widget.size.stroke,
                  leading: leading,
                  trailing: trailing,
                  animate: false,
                ),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _RingPainter(
                    progress: _controller.value,
                    stroke: widget.size.stroke,
                    leading: leading,
                    trailing: trailing,
                    animate: true,
                  ),
                ),
              ),
      ),
    );
  }
}

/// One orbiting segment: how much of the circle it covers, how fast it travels
/// relative to the loop, and where it starts.
typedef _Segment = ({double sweep, double speed, double phase});

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.stroke,
    required this.leading,
    required this.trailing,
    required this.animate,
  });

  /// 0..1 through the loop.
  final double progress;
  final double stroke;
  final Color leading;
  final Color trailing;
  final bool animate;

  /// Trailing arcs first so the leading one paints over them at crossings.
  static const _segments = <_Segment>[
    (sweep: 0.14, speed: 0.66, phase: 0.55),
    (sweep: 0.22, speed: 0.82, phase: 0.28),
    (sweep: 0.30, speed: 1.00, phase: 0.00),
  ];

  static const _turn = 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = stroke / 2;
    final rect = Offset(inset, inset) &
        Size(size.width - stroke, size.height - stroke);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    if (!animate) {
      // Static fallback: a single three-quarter arc, no motion at all.
      canvas.drawArc(rect, -math.pi / 2, _turn * 0.75, false, paint..color = leading);
      return;
    }

    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final isLeading = i == _segments.length - 1;
      // Ease each segment on its own loop. easeInOutCubic maps 0→0 and 1→1, so
      // the segment stays continuous across the wrap instead of jumping.
      final t = Curves.easeInOutCubic.transform(
        (progress * segment.speed + segment.phase) % 1.0,
      );
      canvas.drawArc(
        rect,
        -math.pi / 2 + _turn * t,
        _turn * segment.sweep,
        false,
        paint..color = isLeading ? leading : trailing,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.stroke != stroke ||
      old.leading != leading ||
      old.trailing != trailing ||
      old.animate != animate;
}
