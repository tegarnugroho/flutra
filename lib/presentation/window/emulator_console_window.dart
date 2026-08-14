import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../emulator/emulator_console_page.dart';
import '../theme/app_theme.dart';
import 'window_close_channel.dart';

/// Root widget for the standalone Emulator Console OS window, opened from an
/// AVD's context menu. Runs in its own engine/isolate.
class EmulatorConsoleWindowApp extends StatelessWidget {
  const EmulatorConsoleWindowApp({
    super.key,
    required this.windowController,
    required this.dark,
    required this.avdName,
  });

  final WindowController windowController;
  final bool dark;
  final String avdName;

  @override
  Widget build(BuildContext context) {
    // The main window asks this one to close when the app is quitting;
    // closing it is this window's own job, never the opener's.
    answerCloseRequests(windowController, _handleClose);
    return FluentApp(
      title: 'Emulator Console — $avdName',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: EmulatorConsolePage(
        initialAvd: avdName,
        onClose: _handleClose,
      ),
    );
  }

  /// Closes just this window, like the other task windows do.
  Future<void> _handleClose() async {
    try {
      // close(), never destroy(): destroy() is PostQuitMessage on Windows and
      // every window shares one UI thread — it would end the whole app.
      await windowManager.close();
    } on MissingPluginException {
      await windowController.hide();
    }
  }
}
