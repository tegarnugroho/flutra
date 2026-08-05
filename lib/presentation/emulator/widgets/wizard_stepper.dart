import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/emulator/create_emulator_cubit.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The wizard's progress rail: one numbered circle per step, joined by the
/// lines that fill in behind you.
///
/// Shared by all five steps — the stepper never knows which step's content is
/// on screen, only which step is current.
class WizardStepper extends StatelessWidget {
  const WizardStepper({
    super.key,
    required this.current,
    required this.onTap,
  });

  final WizardStep current;

  /// Called for a step the user has already completed. Upcoming steps are not
  /// tappable — they may not have valid options yet.
  final ValueChanged<WizardStep> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in WizardStep.values) ...[
            _StepMarker(step: step, current: current, onTap: onTap),
            if (step != WizardStep.values.last)
              Expanded(
                child: _Connector(
                  palette: palette,
                  // The segment leaving the active step is half-filled: the
                  // step is underway, not finished.
                  fill: step.index < current.index
                      ? 1.0
                      : step.index == current.index
                      ? 0.5
                      : 0.0,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.palette, required this.fill});

  final AppPalette palette;

  /// 0..1 of the segment that is behind the user.
  final double fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      // Aligns with the middle of the 22px circle above the labels.
      margin: const EdgeInsets.only(top: 10, left: 8, right: 8),
      color: palette.borderStrong,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fill,
        child: Container(color: palette.accent),
      ),
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({
    required this.step,
    required this.current,
    required this.onTap,
  });

  final WizardStep step;
  final WizardStep current;
  final ValueChanged<WizardStep> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final done = step.index < current.index;
    final active = step == current;
    final reachable = step.index <= current.index;

    final Color fill;
    final Color outline;
    final Color foreground;
    if (active) {
      fill = palette.accent;
      outline = palette.accent;
      foreground = onAccent(palette);
    } else if (done) {
      fill = palette.accentBgTint;
      outline = palette.accent;
      foreground = palette.accent;
    } else {
      fill = Colors.transparent;
      outline = palette.borderStrong;
      foreground = palette.textMuted;
    }

    return MouseRegion(
      cursor: reachable ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: reachable ? () => onTap(step) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill,
                border: Border.all(color: outline, width: 1.5),
              ),
              alignment: Alignment.center,
              child: done
                  ? Icon(FluentIcons.check_mark, size: 10, color: foreground)
                  : Text(
                      '${step.index + 1}',
                      style: text.caption.copyWith(color: foreground),
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              step.shortTitle,
              style: text.caption.copyWith(
                color: active ? palette.textPrimary : palette.textMuted,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Readable foreground for text sitting on [AppPalette.accent].
///
/// The mockup calls for dark text on the accent fill, which only holds while
/// the accent is the lighter of the two ramps — pick whichever of the palette's
/// extremes actually contrasts so light mode doesn't end up unreadable.
Color onAccent(AppPalette palette) {
  double luminance(Color c) => c.computeLuminance();
  final dark = palette.brightness == Brightness.dark
      ? const Color(0xFF121214)
      : palette.textPrimary;
  final light = palette.brightness == Brightness.dark
      ? palette.textPrimary
      : const Color(0xFFFFFFFF);
  final onDark = (luminance(palette.accent) + 0.05) / (luminance(dark) + 0.05);
  final onLight = (luminance(light) + 0.05) / (luminance(palette.accent) + 0.05);
  return onDark >= onLight ? dark : light;
}
