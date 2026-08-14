import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

/// Gives the main window resize edges of its own, on the platform where it has
/// none.
///
/// On Windows `TitleBarStyle.hidden` keeps the native frame, so the OS still
/// resizes the window from every edge and this widget is a no-op. On Linux the
/// window is created undecorated (`my_application.cc`) so that neither GTK nor
/// the compositor draws a caption over [CustomTitleBar] — and an undecorated
/// window has no compositor resize borders either. Without this, a Linux window
/// could only ever be the size it started at.
///
/// The strips are transparent and 6px wide, matching what a GTK CSD frame
/// offers, and they sit above the page content — so they are removed while the
/// window is maximized, where there is nothing to resize and they would
/// otherwise swallow clicks along the edges (the content's right-hand scrollbar
/// lives exactly there).
class WindowResizeFrame extends StatefulWidget {
  const WindowResizeFrame({super.key, required this.child});

  final Widget child;

  @override
  State<WindowResizeFrame> createState() => _WindowResizeFrameState();
}

class _WindowResizeFrameState extends State<WindowResizeFrame>
    with WindowListener {
  /// Only Linux loses its frame; everywhere else this widget stays out of the
  /// tree entirely.
  static final bool _needsOwnEdges = Platform.isLinux;

  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!_needsOwnEdges) return;
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    if (_needsOwnEdges) windowManager.removeListener(this);
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    if (!_needsOwnEdges || _isMaximized) return widget.child;
    return DragToResizeArea(resizeEdgeSize: 6, child: widget.child);
  }
}
