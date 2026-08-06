import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

/// Default and floor sizes for the Create Emulator window. It is a task window:
/// big enough for the category grid without scrolling, no bigger.
const Size kWizardWindowSize = Size(720, 640);
const Size kWizardWindowMinSize = Size(640, 560);

/// About is a fixed card: no resize, so default and floor are the same.
const Size kAboutWindowSize = Size(400, 500);

/// The Emulator Console: an AVD picker over a log pane.
const Size kConsoleWindowSize = Size(720, 560);
const Size kConsoleWindowMinSize = Size(560, 420);

/// The Developer Logs viewer wants width for long mono lines.
const Size kDevLogsWindowSize = Size(900, 640);
const Size kDevLogsWindowMinSize = Size(640, 480);

/// The frame a [size]d task window should open at: centred over the window
/// calling this.
///
/// Frame maths lives here, on the creator's side, because only it can read the
/// main window's bounds — a sub-window's engine sees its own window and nothing
/// else. The result rides along in the createWindow arguments and the
/// sub-window applies it verbatim.
///
/// Returns null when the bounds can't be read; the sub-window then falls back
/// to centring on its display.
Future<List<double>?> centeredOverMainWindow(Size size) async {
  try {
    final parent = await windowManager.getBounds();
    return [
      // Centre on the opener rather than the screen, so a multi-monitor setup
      // doesn't fling the task window onto the other display.
      parent.left + (parent.width - size.width) / 2,
      parent.top + (parent.height - size.height) / 2,
      size.width,
      size.height,
    ];
  } catch (_) {
    return null;
  }
}
