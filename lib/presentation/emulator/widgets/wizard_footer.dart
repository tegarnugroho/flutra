import 'package:fluent_ui/fluent_ui.dart';

import '../../common/app_loader.dart';
import '../../common/task_window_title_bar.dart' show kTaskWindowInset;
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'wizard_stepper.dart' show onAccent;

/// The wizard's sticky bottom bar: a contextual summary on the left, Back and
/// the primary action on the right.
///
/// Shared by all five steps. The [summary] slot is what changes — the buttons
/// and their geometry never do.
class WizardFooter extends StatelessWidget {
  const WizardFooter({
    super.key,
    required this.summary,
    required this.onBack,
    required this.onNext,
    this.nextLabel = 'Next',
    this.backLabel = 'Back',
    this.nextDisabledTooltip,
    this.busy = false,
  });

  /// Left-hand slot: the current selection, an error, or a hint.
  final Widget summary;

  final VoidCallback? onBack;

  /// Null disables the primary action and shows [nextDisabledTooltip].
  final VoidCallback? onNext;

  final String nextLabel;

  /// "Cancel" on the wizard's first screen, where Back leaves the window.
  final String backLabel;

  /// Explains why the primary action is unavailable.
  final String? nextDisabledTooltip;

  /// Swaps the primary action's label for a loader.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: kTaskWindowInset),
      decoration: BoxDecoration(
        color: palette.sidebarBg,
        border: Border(
          top: BorderSide(color: palette.border, width: AppShape.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: summary),
          const SizedBox(width: 16),
          _OutlinedButton(label: backLabel, onPressed: onBack),
          const SizedBox(width: 10),
          _PrimaryButton(
            label: nextLabel,
            onPressed: onNext,
            disabledTooltip: nextDisabledTooltip,
            busy: busy,
          ),
        ],
      ),
    );
  }
}

class _OutlinedButton extends StatefulWidget {
  const _OutlinedButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_OutlinedButton> createState() => _OutlinedButtonState();
}

class _OutlinedButtonState extends State<_OutlinedButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final enabled = widget.onPressed != null;
    final foreground = enabled ? palette.textTertiary : palette.textMuted;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered && enabled
                ? palette.surfaceRaised
                : Colors.transparent,
            border: Border.all(
              color: palette.borderStrong,
              width: AppShape.hairline,
            ),
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
          ),
          child: Text(
            widget.label,
            style: text.buttonLabel.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    required this.disabledTooltip,
    required this.busy,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? disabledTooltip;
  final bool busy;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final enabled = widget.onPressed != null && !widget.busy;
    // The fill stays accent even when disabled, so the label keeps its
    // on-accent tone and the Opacity below carries the disabled signal.
    final foreground = onAccent(palette);

    final label = widget.busy
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLoader(size: AppLoaderSize.small, color: foreground),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: text.buttonLabel.copyWith(color: foreground),
              ),
            ],
          )
        : Text(
            widget.label,
            style: text.buttonLabel.copyWith(color: foreground),
          );

    Widget button = MouseRegion(
      // A basic cursor over a disabled primary says "not yet" before the
      // tooltip gets a chance to.
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: Opacity(
          // Dimmed rather than greyed out: it keeps its accent shape, so it
          // still reads as the primary action — just not available yet.
          opacity: enabled ? 1 : 0.45,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: _hovered && enabled
                  ? Color.alphaBlend(
                      palette.textPrimary.withValues(alpha: 0.12),
                      palette.accent,
                    )
                  : palette.accent,
              borderRadius: BorderRadius.circular(AppShape.radiusControl),
            ),
            child: label,
          ),
        ),
      ),
    );

    if (!enabled && widget.disabledTooltip != null) {
      button = Tooltip(message: widget.disabledTooltip!, child: button);
    }
    return button;
  }
}
