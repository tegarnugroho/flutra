import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../about/about_page.dart';
import '../theme/app_theme.dart';
import 'window_close_channel.dart';

/// Root widget for the standalone About OS window.
class AboutWindowApp extends StatelessWidget {
  const AboutWindowApp({
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
    answerCloseRequests(windowController, _handleClose);
    return FluentApp(
      title: 'About',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: AboutPage(onClose: _handleClose),
    );
  }

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
