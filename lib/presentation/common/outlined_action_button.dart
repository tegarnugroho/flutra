import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_loader.dart';

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
    this.hoverLabel,
    this.hoverIcon,
    this.danger = false,
  });

  final IconData icon;
  final String? label;

  /// Shown instead of [label] while the pointer is over the button, so a
  /// button whose action changes (Running → Cancel) can say so.
  final String? hoverLabel;
  final IconData? hoverIcon;
  final VoidCallback? onPressed;

  /// Replaces the icon with a small [AppLoader]. The button keeps its enabled
  /// look so headers don't flicker while a command runs.
  final bool busy;

  /// Smaller padding, for buttons that sit inside a list row.
  final bool dense;

  final String? tooltip;

  /// Destructive styling: error-tinted fill, error border and label. For
  /// actions that take something away — always pair with a confirmation.
  final bool danger;

  @override
  State<OutlinedActionButton> createState() => _OutlinedActionButtonState();
}

class _OutlinedActionButtonState extends State<OutlinedActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // A busy button stays clickable when it offers a hover action (Cancel).
    final enabled =
        widget.onPressed != null && (!widget.busy || widget.hoverLabel != null);
    final label = _hovered ? (widget.hoverLabel ?? widget.label) : widget.label;
    final icon = _hovered ? (widget.hoverIcon ?? widget.icon) : widget.icon;
    final foreground = !enabled
        ? palette.textMuted
        : widget.danger
        ? palette.statusError
        : palette.textTertiary;
    final border = widget.danger && enabled
        ? palette.statusError
        : palette.borderStrong;
    final fill = widget.danger && enabled
        ? palette.dangerSurface
        : Colors.transparent;

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
                ? (widget.danger
                      // Hover deepens the wash rather than switching hue.
                      ? Color.alphaBlend(
                          palette.statusError.withValues(alpha: 0.14),
                          fill,
                        )
                      : palette.surfaceRaised)
                : fill,
            border: Border.all(color: border, width: AppShape.hairline),
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A busy button that offers a hover action (Running → Cancel)
              // shows that icon instead, so the swap stays discoverable.
              if (widget.busy && !(_hovered && widget.hoverIcon != null))
                AppLoader(size: AppLoaderSize.small, color: foreground)
              else
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(child: Icon(icon, size: 13, color: foreground)),
                ),
              if (label != null) ...[
                const SizedBox(width: 7),
                Text(
                  label,
                  style: AppTextStyles.of(
                    context,
                  ).buttonLabel.copyWith(color: foreground),
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
