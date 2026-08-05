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
  const CustomTitleBar({super.key});

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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: kTitleBarHeight,
      color: palette.sidebarBg,
      child: Row(
        children: [
          // The label area doubles as the drag region. [DragToMoveArea] also
          // maps a double-tap to maximize/restore.
          Expanded(
            child: _managesWindow
                ? DragToMoveArea(child: _AppLabel(palette: palette))
                : _AppLabel(palette: palette),
          ),
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

/// App icon + name, left-aligned in the caption.
class _AppLabel extends StatelessWidget {
  const _AppLabel({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // The .ico next to it is for the tray and the installer — Flutter's
          // image pipeline can't decode it, so the caption uses the .png.
          // cacheWidth keeps the 941px source out of the raster cache at full
          // size; it is only ever drawn at 16 logical pixels.
          Image.asset(
            'assets/app_icon.png',
            width: 16,
            height: 16,
            cacheWidth: 64,
            filterQuality: FilterQuality.medium,
            // A missing/undecodable asset must not take the whole shell down.
            errorBuilder: (context, _, _) => Icon(
              FluentIcons.cell_phone,
              size: 15,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Flutter SDK Manager', style: AppTextStyles.titleBar),
        ],
      ),
    );
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

  Color get _background {
    if (widget.isClose) {
      if (_pressed) return AppColors.captionClosePressed;
      if (_hovered) return AppColors.captionCloseHover;
    } else {
      if (_pressed) return AppColors.captionPressed;
      if (_hovered) return AppColors.surfaceRaised;
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
            color: _background,
            alignment: Alignment.center,
            // 10px is the design size of the Segoe chrome glyphs; larger and
            // they stop reading as caption controls.
            child: Icon(
              widget.icon,
              size: 10,
              color: onRed ? Colors.white : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
