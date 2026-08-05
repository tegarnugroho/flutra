import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../application/settings/theme_cubit.dart';
import '../../core/di/injection.dart';
import '../../main.dart' show kAboutWindow;
import 'window_placement.dart';

/// The id of the About window while it is open.
///
/// desktop_multi_window 0.3.0 exposes no "focus this window" call — only
/// show/hide — so a second invocation re-shows the existing one instead of
/// spawning a duplicate.
// TODO(multiwindow): raise/focus the existing window once the plugin can.
String? _aboutWindowId;

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

  final dark = getIt<ThemeCubit>().state == ThemeMode.dark;
  final controller = await WindowController.create(
    WindowConfiguration(
      arguments: jsonEncode({
        'businessId': kAboutWindow,
        'dark': dark,
        // Positions itself before its first paint — see _placeTaskWindow.
        'frame': await centeredOverMainWindow(kAboutWindowSize),
      }),
      hiddenAtLaunch: true,
    ),
  );
  _aboutWindowId = controller.windowId;
}
