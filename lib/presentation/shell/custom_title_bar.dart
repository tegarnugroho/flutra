import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Height of [CustomTitleBar]. Taller than the 32px Windows caption so the app
/// name sits on the same optical line as the sidebar's first item.
const double kTitleBarHeight = 40;

/// Width of a single caption button — the Windows 11 metric.
const double _kCaptionButtonWidth = 46;

/// The app's own window caption, drawn full width above the pane + content.
///
/// The native caption is removed in `main` via
/// `setTitleBarStyle(TitleBarStyle.hidden)`, which keeps the resize borders and
/// Snap behaviour intact — only the caption band is ours. `setAsFrameless()`
/// would take the borders away too, so it is deliberately not used.
///
/// Only the main window gets this treatment: the `desktop_multi_window`
/// sub-windows keep their native title bar (their engines don't register
/// window_manager at all).
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

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  /// Window chrome is only taken over on Windows; elsewhere the bar is just a
  /// header band and the OS keeps drawing its own caption.
  static final bool _managesWindow = Platform.isWindows;

  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!_managesWindow) return;
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    if (_managesWindow) windowManager.removeListener(this);
    super.dispose();
  }

  /// Reads the current state once at startup; afterwards the window events
  /// below keep the glyph in sync, whatever triggered the change (our button,
  /// double-click, Win+Up, or a drag to the top edge).
  Future<void> _syncMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted && maximized != _isMaximized) {
        setState(() => _isMaximized = maximized);
      }
    } catch (_) {
      // window_manager may be briefly unavailable (e.g. after a hot restart).
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() => _syncMaximized();

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

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
          if (_managesWindow) ...[
            _CaptionButton(
              icon: WindowsIcons.chrome_minimize,
              tooltip: 'Minimize',
              onPressed: windowManager.minimize,
            ),
            _CaptionButton(
              icon: _isMaximized
                  ? WindowsIcons.chrome_restore
                  : WindowsIcons.chrome_maximize,
              tooltip: _isMaximized ? 'Restore' : 'Maximize',
              onPressed: _toggleMaximize,
            ),
            _CaptionButton(
              // Routed through close() rather than destroy() so the
              // "close to tray" preference in `AndroidSdkManagerApp` still runs.
              icon: WindowsIcons.chrome_close,
              tooltip: 'Close',
              isClose: true,
              onPressed: windowManager.close,
            ),
          ],
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
        'Flutter SDK Manager',
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

/// One caption button (minimize / maximize-restore / close).
///
/// Fixed 46px wide and full bar height with no surrounding padding, so a cursor
/// flung into the top-right corner still lands on the close button.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Close gets the red hover treatment instead of the neutral overlay.
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  Color _background(AppPalette palette) {
    if (widget.isClose) {
      if (_pressed) return palette.captionClosePressed;
      if (_hovered) return palette.captionCloseHover;
    } else {
      if (_pressed) return palette.captionPressed;
      if (_hovered) return palette.captionHover;
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final onRed = widget.isClose && (_hovered || _pressed);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        // Raw gesture handling rather than a Button: no ripple, no rounded
        // corners, no padding — the caption buttons must fill their slot.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: Container(
            width: _kCaptionButtonWidth,
            height: kTitleBarHeight,
            color: _background(palette),
            alignment: Alignment.center,
            // 10px is the design size of the Segoe chrome glyphs; larger and
            // they stop reading as caption controls.
            child: Icon(
              widget.icon,
              size: 10,
              color: onRed
                  ? palette.captionCloseForeground
                  : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
