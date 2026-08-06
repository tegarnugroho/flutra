import 'package:fluent_ui/fluent_ui.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Default and floor sizes for the Create Emulator window. It is a task window:
/// big enough for the category grid without scrolling, no bigger.
const Size kWizardWindowSize = Size(720, 640);
const Size kWizardWindowMinSize = Size(640, 560);

/// About is a fixed card: no resize, so default and floor are the same.
const Size kAboutWindowSize = Size(400, 500);

/// The Developer Logs viewer wants width for long mono lines.
const Size kDevLogsWindowSize = Size(900, 640);
const Size kDevLogsWindowMinSize = Size(640, 480);

/// The frame a [size]d task window should open at: centred over the window
/// calling this, kept inside the display that window is on.
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
    final workArea = await _workAreaFor(parent);
    final frame = centeredFrame(
      parent: parent,
      workArea: workArea,
      size: size,
    );
    return [frame.left, frame.top, frame.width, frame.height];
  } catch (_) {
    return null;
  }
}

/// The usable area of the display [parent] sits on.
///
/// Both this and [WindowManager.getBounds] are read in the same coordinate
/// space window_manager itself mixes them in (see its `calcWindowPosition`), so
/// no DPI conversion happens here — introducing one would put the frame in a
/// space neither API expects.
///
/// Null when the displays cannot be read, which leaves the frame unclamped
/// rather than clamped to a guess.
Future<Rect?> _workAreaFor(Rect parent) async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    if (displays.isEmpty) return null;

    Rect areaOf(Display display) {
      final origin = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
    }

    // The display holding the parent's centre: a window straddling two screens
    // belongs to the one it is mostly on.
    for (final display in displays) {
      final area = areaOf(display);
      if (area.contains(parent.center)) return area;
    }
    return areaOf(displays.first);
  } catch (_) {
    return null;
  }
}

/// Centres [size] over [parent], then pulls it back inside [workArea].
///
/// Pure so the multi-monitor and edge cases can be tested without a screen.
/// Clamping matters when the opener sits near an edge or on a small display:
/// a centred child would otherwise open half off-screen, or under the taskbar,
/// which the work area excludes.
///
/// A window larger than the work area is pinned to its top-left rather than
/// resized — the caller chose that size, and a wizard that silently shrinks is
/// worse than one that overflows a small screen.
Rect centeredFrame({
  required Rect parent,
  required Size size,
  Rect? workArea,
}) {
  var left = parent.left + (parent.width - size.width) / 2;
  var top = parent.top + (parent.height - size.height) / 2;

  if (workArea != null) {
    if (size.width < workArea.width) {
      left = left.clamp(workArea.left, workArea.right - size.width);
    } else {
      left = workArea.left;
    }
    if (size.height < workArea.height) {
      top = top.clamp(workArea.top, workArea.bottom - size.height);
    } else {
      top = workArea.top;
    }
  }

  return Rect.fromLTWH(left, top, size.width, size.height);
}
