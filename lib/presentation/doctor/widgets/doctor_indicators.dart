import 'package:fluent_ui/fluent_ui.dart';

import '../../common/app_loader.dart';
import '../../common/status_dot.dart';
import '../../theme/app_colors.dart';
import '../doctor_animations.dart';

/// A status dot that pops in when it first appears.
class PoppingStatusDot extends StatelessWidget {
  const PoppingStatusDot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (DoctorAnimations.reduced(context)) {
      return StatusDot(color: color, size: size);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: DoctorAnimations.dotPop,
      curve: DoctorAnimations.dotPopCurve,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: StatusDot(color: color, size: size),
    );
  }
}

/// The dot for the check currently being waited on: accent fill with a soft
/// ring expanding out of it.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, this.size = 6});

  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DoctorAnimations.pulse,
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dot = StatusDot(color: palette.accent, size: widget.size);
    if (DoctorAnimations.reduced(context)) return dot;
    // Isolated so the ring's 60fps repaint never dirties the rest of the list.
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size * 3,
        height: widget.size * 3,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0) * 0.45,
                    child: Container(
                      width: widget.size + (widget.size * 2 * t),
                      height: widget.size + (widget.size * 2 * t),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.accent, width: 1),
                      ),
                    ),
                  ),
                  ?child,
                ],
              );
            },
            child: dot,
          ),
        ),
      ),
    );
  }
}

/// A hollow dot marking a check that hasn't run yet.
class PendingDot extends StatelessWidget {
  const PendingDot({super.key, this.size = 6});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.textMuted, width: AppShape.hairline),
      ),
    );
  }
}

/// Text with a trailing "…" that cycles through one, two and three dots.
class AnimatedEllipsisText extends StatefulWidget {
  const AnimatedEllipsisText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<AnimatedEllipsisText> createState() => _AnimatedEllipsisTextState();
}

class _AnimatedEllipsisTextState extends State<AnimatedEllipsisText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DoctorAnimations.ellipsis,
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DoctorAnimations.reduced(context)) {
      return Text('${widget.text}…', style: widget.style);
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final dots = '.' * (1 + (_controller.value * 3).floor() % 3);
          return Text('${widget.text}$dots', style: widget.style);
        },
      ),
    );
  }
}

/// A small spinner shown at the end of the running row.
class RowSpinner extends StatelessWidget {
  const RowSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLoader(size: AppLoaderSize.small);
  }
}
