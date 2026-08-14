import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';

/// Asks a sub-window to close itself.
///
/// desktop_multi_window 0.3.0 has no `WindowController.close()` — only
/// show/hide — so "shut this other window down" has to travel over the
/// per-window channel the plugin does expose, and be carried out by the window
/// that owns it. That is not a workaround so much as the only correct shape:
/// each window's `window_manager` is bound to its own GtkWindow/HWND, so the
/// window that closes it is the only one that can close just it.
const String kCloseWindowMethod = 'flutra.closeWindow';

/// How long the main window waits for its children to actually go away.
///
/// Closing a window tears an engine down, which is not instant and not
/// awaitable from outside it — the acknowledgement below comes back before the
/// window is gone, by design. Destroying the main window while a child engine
/// is still unwinding is what crashed the process on Linux, so this is the
/// margin that keeps the two apart.
const Duration _childDrain = Duration(milliseconds: 600);

/// Registers [close] as this sub-window's answer to a close request.
///
/// The request is acknowledged immediately and [close] runs on a later turn of
/// this window's own event loop. Closing inside the call would tear this
/// engine's channel down while the opener is still awaiting a reply on it —
/// on Linux that aborted the whole process with `g_mutex_clear() called on
/// uninitialised or locked mutex`.
void answerCloseRequests(
  WindowController controller,
  Future<void> Function() close,
) {
  controller.setWindowMethodHandler((call) async {
    if (call.method == kCloseWindowMethod) {
      Timer(Duration.zero, close);
    }
    return null;
  });
}

/// Whether the window carrying [arguments] is one this app opened.
///
/// The main window is not created by the plugin — the runner makes it and the
/// plugin adopts it, with no arguments. Every window this app opens is created
/// through `WindowController.create` with its `businessId` encoded in them. So
/// "has arguments" is what separates a sub-window from the one that must be
/// closed last, and getting it backwards would have the main window ask itself
/// to close.
///
/// Pure, because "which of the open windows does closing the app take with it"
/// is worth being able to answer without opening any.
bool isChildWindow(String arguments) => arguments.trim().isNotEmpty;

/// Closes every sub-window, then gives their engines time to unwind.
///
/// Called by the main window before it destroys itself, so that "closing the
/// main window closes the app" does not mean "the app dies with child engines
/// still running". Best-effort throughout: a child that has already gone, or
/// never answered, must not be able to keep the app open.
Future<void> closeChildWindows() async {
  try {
    final all = await WindowController.getAll();
    final children = all.where((w) => isChildWindow(w.arguments)).toList();
    if (children.isEmpty) return;

    for (final child in children) {
      try {
        await child.invokeMethod<void>(kCloseWindowMethod);
      } catch (_) {
        // Gone already, or never registered a handler — either way there is
        // nothing left to ask.
      }
    }
    await Future<void>.delayed(_childDrain);
  } catch (_) {
    // The plugin is unavailable (hot restart). Closing the main window is
    // still the right thing to do.
  }
}
