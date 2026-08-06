import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../application/settings/theme_cubit.dart';
import '../../core/di/injection.dart';
import 'task_window_routes.dart';
import 'warm_window_pool.dart';
import 'window_placement.dart';

/// The id of the About window while it is open.
///
/// desktop_multi_window 0.3.0 exposes no "focus this window" call — only
/// show/hide — so a second invocation re-shows the existing one instead of
/// spawning a duplicate.
// TODO(multiwindow): raise/focus the existing window once the plugin can.
String? _aboutWindowId;

/// Business ids with an open already in flight.
///
/// A double-click used to spawn two windows: the first click's engine is still
/// booting when the second arrives, so nothing yet exists to find.
final Set<String> _opening = {};

/// Opens the About window, or re-shows it when it is already up.
Future<void> openAboutWindow() async {
  final existing = _aboutWindowId;
  if (existing != null) {
    final open = await WindowController.getAll();
    final match = open.where((w) => w.windowId == existing);
    if (match.isNotEmpty) {
      await match.first.show();
      return;
    }
    // It was closed behind our back; fall through and make a new one.
    _aboutWindowId = null;
  }

  _aboutWindowId =
      await _openTaskWindow(kAboutWindow, size: kAboutWindowSize) ??
          _aboutWindowId;
}

/// Opens the Create Emulator wizard. Unlike About, several may be open at once
/// — each is an independent draft.
Future<void> openCreateEmulatorWindow() =>
    _openTaskWindow(kCreateEmulatorWindow, size: kWizardWindowSize);

/// Opens the Developer Logs viewer.
Future<void> openDevLogsWindow() =>
    _openTaskWindow(kDevLogsWindow, size: kDevLogsWindowSize);

/// Opens the emulator console for [avdName].
Future<void> openEmulatorConsoleWindow(String avdName) => _openTaskWindow(
      kEmulatorConsoleWindow,
      size: kConsoleWindowSize,
      extra: {'avd': avdName},
    );

/// Opens a task window, preferring the warm one.
///
/// Returns the id of the window that took the job — warm or freshly created —
/// so a caller that must not open twice can find it again. Null only when the
/// open was dropped as a duplicate.
Future<String?> _openTaskWindow(
  String businessId, {
  required Size size,
  Map<String, dynamic> extra = const {},
}) async {
  // Debounce per window kind. Two wizards at once is a feature; two from one
  // double-click is not.
  if (!_opening.add(businessId)) return null;

  final trace = WindowOpenTrace(businessId);
  try {
    final args = <String, dynamic>{
      'businessId': businessId,
      'dark': getIt<ThemeCubit>().state == ThemeMode.dark,
      // Worked out here because only this engine can see the main window; the
      // target applies it verbatim while still hidden.
      'frame': await centeredOverMainWindow(size),
      ...extra,
    };

    final pool = getIt<WarmWindowPool>();
    trace.mark('prepared');
    final warm = await pool.acquire(args);
    if (warm != null) {
      // The warm window shows itself once the new content has rendered.
      trace.done(warm: true);
      return warm.windowId;
    }

    trace.mark('create');
    final controller = await WindowController.create(
      WindowConfiguration(arguments: jsonEncode(args), hiddenAtLaunch: true),
    );
    trace.done(warm: false);
    return controller.windowId;
  } finally {
    _opening.remove(businessId);
  }
}
