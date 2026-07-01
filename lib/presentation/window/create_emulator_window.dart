import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../emulator/create_emulator_page.dart';
import '../theme/app_theme.dart';

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
      await windowManager.close();
    } on MissingPluginException {
      await windowController.hide();
    }
  }
}
