import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../../common/window_caption_buttons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The horizontal inset every band of the wizard window shares — title bar,
/// stepper, content and footer all start on this line.
const double kWizardInset = 22;

/// The wizard window's caption, which doubles as its header.
///
/// One 40px band instead of a caption plus a page heading: back button, title,
/// the selected device as a chip, drag area, then minimize and close. No
/// maximize — a task window has no use for the whole screen.
class WizardTitleBar extends StatelessWidget {
  const WizardTitleBar({
    super.key,
    required this.onBack,
    required this.backTooltip,
    required this.onClose,
    this.contextLabel,
  });

  /// Back one level: the device list falls back to categories, and the
  /// categories screen closes the window.
  final VoidCallback onBack;

  /// Names what Back will actually do at this level.
  final String backTooltip;

  final VoidCallback onClose;

  /// Shown as a muted pill after the title once a device is picked.
  final String? contextLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    return Container(
      height: kCaptionHeight,
      color: palette.sidebarBg,
      child: Row(
        children: [
          const SizedBox(width: kWizardInset - 6),
          WizardIconButton(
            icon: FluentIcons.back,
            tooltip: backTooltip,
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
          Text('Create emulator', style: text.titleBar),
          if (contextLabel != null) ...[
            const SizedBox(width: 8),
            _ContextChip(label: contextLabel!),
          ],
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

/// A small pill naming the current selection, so the title bar carries context
/// once the user is deeper in the wizard.
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.label});

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
/// need to read as buttons rather than as bare glyphs.
class WizardIconButton extends StatefulWidget {
  const WizardIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<WizardIconButton> createState() => _WizardIconButtonState();
}

class _WizardIconButtonState extends State<WizardIconButton> {
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
      // Unlike the main window's chrome buttons this one rests visible: it is
      // the only way back, so it must not read as a bare glyph.
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
