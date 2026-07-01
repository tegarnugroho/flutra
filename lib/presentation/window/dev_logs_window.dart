import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../settings/dev_logs_page.dart';
import '../theme/app_theme.dart';

/// Root widget for the standalone Developer Logs OS window.
class DevLogsWindowApp extends StatelessWidget {
  const DevLogsWindowApp({
    super.key,
    required this.windowController,
    required this.dark,
  });

  final WindowController windowController;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Developer Logs',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const DevLogsPage(),
    );
  }
}
