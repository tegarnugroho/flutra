import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'window_caption_buttons.dart';

/// The horizontal inset every band of a task window shares — title bar,
/// toolbar, content and footer all start on this line.
const double kTaskWindowInset = 22;

/// The caption of a secondary window, which doubles as its header.
///
/// One 40px band instead of a caption plus a page heading. Shared by the
/// Create Emulator wizard and the Developer Logs viewer — a task window has a
/// fixed job, so there is no maximize button.
class TaskWindowTitleBar extends StatelessWidget {
  const TaskWindowTitleBar({
    super.key,
    required this.title,
    required this.onClose,
    this.leading,
    this.icon,
    this.trailing,
  });

  final String title;

  /// What the caption's close button does. Windows that need to confirm or
  /// clean up first pass their own handler.
  final VoidCallback onClose;

  /// Control in the app-icon slot, e.g. a back button.
  final Widget? leading;

  /// Glyph in the app-icon slot, used when there is no [leading] control.
  final IconData? icon;

  /// Sits after the title — a context chip, a count pill.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    return Container(
      height: kCaptionHeight,
      color: palette.sidebarBg,
      child: Row(
        children: [
          const SizedBox(width: kTaskWindowInset - 6),
          if (leading != null)
            leading!
          else if (icon != null)
            Icon(icon, size: 15, color: palette.textSecondary),
          const SizedBox(width: 10),
          Text(title, style: text.titleBar),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          Expanded(child: DragToMoveArea(child: Container())),
          WindowCaptionButtons(
            showMaximize: false,
            buttonWidth: 42,
            onClose: onClose,
          ),
        ],
      ),
    );
  }
}

/// A muted pill for a count or a context label in the title bar.
class TitleBarChip extends StatelessWidget {
  const TitleBarChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: text.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A 26px square icon button with a resting surface, for chrome actions that
/// must read as buttons rather than as bare glyphs.
class TitleBarIconButton extends StatefulWidget {
  const TitleBarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<TitleBarIconButton> createState() => _TitleBarIconButtonState();
}

class _TitleBarIconButtonState extends State<TitleBarIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = widget.onPressed != null;

    final Color background;
    if (!enabled) {
      background = Colors.transparent;
    } else if (_pressed) {
      background = palette.captionPressed;
    } else if (_hovered) {
      background = palette.borderStrong;
    } else {
      // Unlike the caption glyphs this one rests visible: it is often the only
      // way back, so it must not read as decoration.
      background = palette.surfaceRaised;
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppShape.radiusControl),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovered && enabled
                  ? palette.textPrimary
                  : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
