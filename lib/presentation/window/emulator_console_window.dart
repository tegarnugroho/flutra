import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../emulator/emulator_console_page.dart';
import '../theme/app_theme.dart';

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
    return FluentApp(
      title: 'Emulator Console — $avdName',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: EmulatorConsolePage(initialAvd: avdName),
    );
  }
}
