import 'dart:io';
import '../../core/constants/app_info.dart';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../common/window_caption_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Height of [CustomTitleBar]. Taller than the 32px Windows caption so the app
/// name sits on the same optical line as the sidebar's first item.
const double kTitleBarHeight = kCaptionHeight;

/// The app's own window caption, drawn full width above the pane + content.
///
/// The native caption is removed in `main` via
/// `setTitleBarStyle(TitleBarStyle.hidden)`, which keeps the resize borders and
/// Snap behaviour intact — only the caption band is ours. `setAsFrameless()`
/// would take the borders away too, so it is deliberately not used.
///
/// The Create Emulator window draws its own variant of this band from the same
/// building blocks — see `WizardTitleBar`.
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key, this.leading, this.actions = const []});

  /// Control placed where an app icon would normally sit, before the app name.
  final Widget? leading;

  /// Shell controls placed after the app name — usually
  /// [TitleBarActionButton]s. Everything to their right stays drag area.
  final List<Widget> actions;

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> {
  /// Window chrome is only taken over on Windows; elsewhere the bar is just a
  /// header band and the OS keeps drawing its own caption.
  static final bool _managesWindow = Platform.isWindows;

  /// Turns [child] into a window-drag handle, or leaves it alone on platforms
  /// where the OS still owns the caption.
  Widget _draggable(Widget child) =>
      _managesWindow ? DragToMoveArea(child: child) : child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: kTitleBarHeight,
      color: palette.sidebarBg,
      child: Row(
        children: [
          // The label and the empty stretch after the actions both drag the
          // window; [DragToMoveArea] also maps a double-tap to maximize.
          if (widget.leading != null) ...[
            const SizedBox(width: 6),
            widget.leading!,
          ],
          _draggable(_AppLabel(hasLeading: widget.leading != null)),
          if (widget.actions.isNotEmpty) ...[
            const SizedBox(width: 6),
            ...widget.actions,
          ],
          Expanded(child: _draggable(const SizedBox.expand())),
          // Close routes through windowManager.close() so the "close to tray"
          // preference in `AndroidSdkManagerApp` still runs.
          if (_managesWindow) const WindowCaptionButtons(),
        ],
      ),
    );
  }
}

/// The app name, left-aligned in the caption.
///
/// No app icon: the leading slot carries the sidebar toggle instead, and a
/// glyph plus an icon button side by side just reads as noise.
class _AppLabel extends StatelessWidget {
  const _AppLabel({required this.hasLeading});

  /// Tightens the left inset — the leading control already provides the gap.
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: hasLeading ? 8 : 12, right: 4),
      child: Text(
        AppInfo.name,
        style: AppTextStyles.of(context).titleBar,
      ),
    );
  }
}

/// A shell control in the title bar (sidebar toggle, search, back/forward).
///
/// Smaller and rounded, unlike the caption buttons — these are app affordances,
/// not window chrome, and they aren't corner-fling targets. A null [onPressed]
/// renders the disabled look and swallows hover.
class TitleBarActionButton extends StatefulWidget {
  const TitleBarActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Keeps the hover surface on to show a toggled-on state.
  final bool isActive;

  @override
  State<TitleBarActionButton> createState() => _TitleBarActionButtonState();
}

class _TitleBarActionButtonState extends State<TitleBarActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final Color background;
    if (!_enabled) {
      background = Colors.transparent;
    } else if (_pressed) {
      background = palette.captionPressed;
    } else if (_hovered || widget.isActive) {
      background = palette.surfaceRaised;
    } else {
      background = Colors.transparent;
    }

    final button = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 14,
            color: _enabled ? palette.textSecondary : palette.textMuted,
          ),
        ),
      ),
    );

    // A tooltip on a disabled control reads as a broken affordance.
    if (!_enabled) return button;
    return Tooltip(message: widget.tooltip, child: button);
  }
}
