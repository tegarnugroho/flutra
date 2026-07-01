import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../application/emulator/emulator_events.dart';
import '../application/settings/theme_cubit.dart';
import '../core/di/injection.dart';
import '../infrastructure/settings/settings_service.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

/// Root widget of the main window: wires the Fluent theme to the [ThemeCubit],
/// hosts the shell, and reloads emulator lists whenever the window regains focus
/// (e.g. after the separate Create-Emulator window closes).
class AndroidSdkManagerApp extends StatefulWidget {
  const AndroidSdkManagerApp({super.key});

  @override
  State<AndroidSdkManagerApp> createState() => _AndroidSdkManagerAppState();
}

class _AndroidSdkManagerAppState extends State<AndroidSdkManagerApp>
    with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initTray();
  }

  Future<void> _initTray() async {
    try {
      await windowManager.setPreventClose(true);
      // Use the app icon bundled next to the executable (asset-relative paths
      // aren't reliably resolved by the tray on Windows).
      final assetIcon = p.join(p.dirname(Platform.resolvedExecutable), 'data',
          'flutter_assets', 'assets', 'app_icon.ico');
      await trayManager
          .setIcon(File(assetIcon).existsSync() ? assetIcon : 'assets/app_icon.ico');
      await trayManager.setToolTip('Flutter SDK Manager');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Open Flutter SDK Manager'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit'),
      ]));
    } catch (_) {
      // Tray/window plugins may be unavailable (e.g. after a hot restart).
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    // A sub-window (e.g. Create Emulator) may have changed the AVD set.
    getIt<EmulatorEvents>().emitChanged();
  }

  @override
  void onWindowClose() async {
    // Honour the "close to tray" preference; otherwise really quit.
    final toTray = getIt<SettingsService>().settings.closeToTray;
    if (toTray) {
      await windowManager.hide();
    } else {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() => _restoreWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'show':
        await _restoreWindow();
      case 'exit':
        await windowManager.setPreventClose(false);
        await trayManager.destroy();
        await windowManager.destroy();
    }
  }

  Future<void> _restoreWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: getIt<ThemeCubit>(),
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, mode) {
          return FluentApp(
            title: 'Flutter SDK Manager',
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
