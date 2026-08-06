import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'window_placement.dart';

/// Business id marking the standalone Create-Emulator window.
const String kCreateEmulatorWindow = 'createEmulator';

/// Business id marking the standalone Emulator-Console window.
const String kEmulatorConsoleWindow = 'emulatorConsole';

/// Business id marking the standalone Developer-Logs window.
const String kDevLogsWindow = 'devLogs';

/// Business id marking the standalone About window.
const String kAboutWindow = 'about';

/// A window created ahead of time, waiting to be told what to be.
///
/// It boots to an empty themed surface and stays hidden. See [WarmWindowPool].
const String kStandbyWindow = 'standby';

/// The IPC method a warm window is told to become something with.
const String kNavigateMethod = 'navigate';

/// The IPC method that proves a warm window's engine is still answering.
const String kPingMethod = 'ping';

/// The IPC method that asks a standby window to go away.
const String kCloseMethod = 'close';

/// The console had no declared size and opened wherever the OS put it. It is
/// the one task window that was never placed; giving it a frame is what lets
/// it come out of the warm pool like the others.
const Size kConsoleWindowSize = Size(720, 520);
const Size kConsoleWindowMinSize = Size(560, 420);

/// The shape a task window takes: how big, how small it may get, and whether
/// the user may resize it at all.
class TaskWindowChrome {
  const TaskWindowChrome({
    required this.size,
    required this.minSize,
    this.resizable = true,
  });

  final Size size;
  final Size minSize;
  final bool resizable;
}

/// One source of truth for every task window's shape, read both when a window
/// boots into a job and when a warm one is handed one.
const Map<String, TaskWindowChrome> kTaskWindowChrome = {
  kCreateEmulatorWindow: TaskWindowChrome(
    size: kWizardWindowSize,
    minSize: kWizardWindowMinSize,
  ),
  kEmulatorConsoleWindow: TaskWindowChrome(
    size: kConsoleWindowSize,
    minSize: kConsoleWindowMinSize,
  ),
  kDevLogsWindow: TaskWindowChrome(
    size: kDevLogsWindowSize,
    minSize: kDevLogsWindowMinSize,
  ),
  // A fixed card: nothing in it reflows, so resizing only ever makes it worse.
  kAboutWindow: TaskWindowChrome(
    size: kAboutWindowSize,
    minSize: kAboutWindowSize,
    resizable: false,
  ),
};

/// Sizes and positions this window for [route], while it is still hidden.
///
/// The frame in [args] was worked out by the opener, which is the only engine
/// that can see the main window; this side applies it verbatim. A missing or
/// malformed one falls back to centring on this window's own display — never
/// show unpositioned.
Future<void> applyWindowChrome(String route, Map<String, dynamic> args) async {
  final chrome = kTaskWindowChrome[route];
  if (chrome == null) return;

  await _tryWindow(() async {
    // Order matters: a minimum larger than the incoming frame would otherwise
    // silently grow it.
    await windowManager.setResizable(chrome.resizable);
    await windowManager.setMinimumSize(chrome.minSize);

    final frame = (args['frame'] as List?)?.cast<num>();
    if (frame == null || frame.length != 4) {
      await windowManager.setSize(chrome.size);
      await windowManager.setAlignment(Alignment.center);
      return;
    }
    await windowManager.setBounds(
      Rect.fromLTWH(
        frame[0].toDouble(),
        frame[1].toDouble(),
        frame[2].toDouble(),
        frame[3].toDouble(),
      ),
    );
  });
}

/// Runs a window_manager call, tolerating an engine where the plugin is
/// missing (hot restart, or a platform that has no such window).
Future<void> _tryWindow(Future<void> Function() action) async {
  try {
    await action();
  } on MissingPluginException catch (_) {
    // Nothing to configure — the window keeps its native defaults.
  } catch (_) {}
}
