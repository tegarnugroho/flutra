import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';

/// Height of a caption band, and of the buttons that fill it.
const double kCaptionHeight = 40;

/// Width of a single caption button — the Windows 11 metric.
const double kCaptionButtonWidth = 46;

/// The minimize / maximize-restore / close cluster.
///
/// Shared by every window the app draws its own caption for: the main shell and
/// the Create Emulator window. A task window passes `showMaximize: false` —
/// it has a fixed job and no reason to fill the screen.
class WindowCaptionButtons extends StatefulWidget {
  const WindowCaptionButtons({
    super.key,
    this.showMaximize = true,
    this.buttonWidth = kCaptionButtonWidth,
    this.onClose,
  });

  final bool showMaximize;

  final double buttonWidth;

  /// Overrides what the close button does. Defaults to `windowManager.close()`,
  /// which lets a window's own close handler decide (the main window honours
  /// "close to tray"; the wizard confirms before discarding).
  final VoidCallback? onClose;

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowCaptionButton(
          icon: WindowsIcons.chrome_minimize,
          tooltip: 'Minimize',
          width: widget.buttonWidth,
          onPressed: windowManager.minimize,
        ),
        if (widget.showMaximize)
          WindowCaptionButton(
            icon: _isMaximized
                ? WindowsIcons.chrome_restore
                : WindowsIcons.chrome_maximize,
            tooltip: _isMaximized ? 'Restore' : 'Maximize',
            width: widget.buttonWidth,
            onPressed: _toggleMaximize,
          ),
        WindowCaptionButton(
          icon: WindowsIcons.chrome_close,
          tooltip: 'Close',
          isClose: true,
          width: widget.buttonWidth,
          onPressed: widget.onClose ?? windowManager.close,
        ),
      ],
    );
  }
}

/// One caption button (minimize / maximize-restore / close).
///
/// Full bar height with no surrounding padding, so a cursor flung into the
/// top-right corner still lands on the close button.
class WindowCaptionButton extends StatefulWidget {
  const WindowCaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.width = kCaptionButtonWidth,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double width;

  /// Close gets the red hover treatment instead of the neutral overlay.
  final bool isClose;

  @override
  State<WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<WindowCaptionButton> {
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
            width: widget.width,
            height: kCaptionHeight,
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
