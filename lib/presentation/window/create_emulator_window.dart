import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../emulator/create_emulator_page.dart';
import '../theme/app_theme.dart';
import 'window_close_channel.dart';

/// Root widget for the standalone Create-Emulator OS window.
///
/// Runs in its own Flutter engine/isolate. On completion it notifies the main
/// window (id 0) so the emulator list can refresh, then closes itself.
class CreateEmulatorWindowApp extends StatelessWidget {
  const CreateEmulatorWindowApp({
    super.key,
    required this.windowController,
    required this.dark,
  });

  final WindowController windowController;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    // The main window asks this one to close when the app is quitting;
    // closing it is this window's own job, never the opener's.
    answerCloseRequests(windowController, () => _handleClose(false));
    return FluentApp(
      title: 'Create Emulator',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: CreateEmulatorPage(onClose: _handleClose),
    );
  }

  Future<void> _handleClose(bool created) async {
    // The main window reloads its AVD list when it regains focus, so simply
    // closing this window is enough to keep both in sync. Guard the call in case
    // window_manager's native side is unavailable (e.g. after a hot restart).
    try {
      // The wizard holds preventClose so the caption's X can run the discard
      // check. Release it before closing, or WM_CLOSE bounces straight back
      // into onWindowClose and the window never goes away.
      await windowManager.setPreventClose(false);
      // close(), never destroy(): window_manager's destroy() is PostQuitMessage
      // on Windows, and every window shares one UI thread — it would end the
      // whole app instead of this one window. close() posts SC_CLOSE to this
      // window's own handle.
      await windowManager.close();
    } on MissingPluginException {
      await windowController.hide();
    }
  }
}
