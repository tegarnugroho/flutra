import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../doctor_animations.dart';

/// The thin run-progress bar under the status line.
///
/// While running it fills to [progress] (already time-weighted by the caller).
/// When [completed] flips true it fills to 100%, recolours to [completionColor],
/// holds, then fades out.
class DoctorProgressBar extends StatefulWidget {
  const DoctorProgressBar({
    super.key,
    required this.progress,
    required this.completed,
    required this.completionColor,
  });

  final double progress;
  final bool completed;
  final Color completionColor;

  @override
  State<DoctorProgressBar> createState() => _DoctorProgressBarState();
}

class _DoctorProgressBarState extends State<DoctorProgressBar> {
  Timer? _hold;
  bool _faded = false;

  @override
  void didUpdateWidget(covariant DoctorProgressBar old) {
    super.didUpdateWidget(old);
    if (widget.completed && !old.completed) {
      _hold?.cancel();
      _hold = Timer(DoctorAnimations.progressHold, () {
        if (mounted) setState(() => _faded = true);
      });
    } else if (!widget.completed && old.completed) {
      _hold?.cancel();
      _faded = false;
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final value = widget.completed ? 1.0 : widget.progress.clamp(0.0, 1.0);
    final color = widget.completed ? widget.completionColor : palette.accent;

    return AnimatedOpacity(
      opacity: _faded ? 0 : 1,
      duration: DoctorAnimations.scale(context, DoctorAnimations.progressFade),
      child: SizedBox(
        height: DoctorAnimations.progressHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(
                        DoctorAnimations.progressHeight),
                  ),
                  child: const SizedBox(width: double.infinity),
                ),
                AnimatedContainer(
                  duration:
                      DoctorAnimations.scale(context, DoctorAnimations.progress),
                  curve: DoctorAnimations.progressCurve,
                  width: constraints.maxWidth * value,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(
                        DoctorAnimations.progressHeight),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
