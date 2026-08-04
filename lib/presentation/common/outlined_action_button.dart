import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// The app's standard action button: hairline outline, no fill, muted label.
///
/// Used for every page-header action and for inline actions inside grouped
/// lists. Omit [label] for an icon-only button (e.g. the ⋯ overflow), set
/// [busy] to spin the icon, and set [dense] for the smaller in-row variant.
class OutlinedActionButton extends StatefulWidget {
  const OutlinedActionButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.busy = false,
    this.dense = false,
    this.tooltip,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;

  /// Spins the icon. The button keeps its enabled look so headers don't
  /// flicker while a command runs.
  final bool busy;

  /// Smaller padding, for buttons that sit inside a list row.
  final bool dense;

  final String? tooltip;

  @override
  State<OutlinedActionButton> createState() => _OutlinedActionButtonState();
}

class _OutlinedActionButtonState extends State<OutlinedActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant OutlinedActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.busy && _spin.isAnimating) {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = widget.onPressed != null && !widget.busy;
    final foreground = enabled ? palette.textTertiary : palette.textMuted;

    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: Container(
          padding: widget.dense
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 3)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: _spin,
                child: Icon(widget.icon, size: 13, color: foreground),
              ),
              if (widget.label != null) ...[
                const SizedBox(width: 7),
                Text(
                  widget.label!,
                  style: AppTextStyles.buttonLabel.copyWith(color: foreground),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
