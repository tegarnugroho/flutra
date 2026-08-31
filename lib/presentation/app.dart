import 'dart:async';
import 'dart:io';
import '../core/constants/app_info.dart';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:logging/logging.dart';
import 'package:smooth_window_close/smooth_window_close.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../application/emulator/emulator_events.dart';
import '../application/settings/theme_cubit.dart';
import '../core/di/injection.dart';
import '../infrastructure/settings/settings_service.dart';
import 'common/window_resize_frame.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';
import 'window/window_close_channel.dart';

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
  late final SmoothWindowCloser _windowCloser;

  @override
  void initState() {
    super.initState();
    _windowCloser = SmoothWindowCloser(
      shouldCloseToTray: () => getIt<SettingsService>().settings.closeToTray,
      onSaveState: () async {
        _saveBoundsTimer?.cancel();
        await _saveWindowBounds();
      },
      onCleanup: () async {
        await closeChildWindows();
        await _destroyTray();
      },
      onError: (error, stackTrace) {
        Logger('shutdown').warning('Shutdown step failed', error, stackTrace);
      },
    );
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initTray();
  }

  Future<void> _initTray() async {
    try {
      await _windowCloser.initialize();
    } catch (_) {
      // window_manager may be unavailable after hot restart.
    }

    try {
      // Use the app icon bundled next to the executable (asset-relative paths
      // aren't reliably resolved by the tray on Windows).
      final assetIcon = p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        'assets',
        'app_icon.ico',
      );
      await trayManager.setIcon(
        File(assetIcon).existsSync() ? assetIcon : 'assets/app_icon.ico',
      );
      await trayManager.setToolTip(AppInfo.name);
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Open ${AppInfo.name}'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: 'Exit'),
          ],
        ),
      );
    } catch (_) {
      // Tray/window plugins may be unavailable (e.g. after a hot restart).
    }
  }

  Timer? _saveBoundsTimer;

  @override
  void dispose() {
    _saveBoundsTimer?.cancel();
    unawaited(_windowCloser.dispose());
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
  void onWindowMoved() => _scheduleSaveBounds();

  @override
  void onWindowResized() => _scheduleSaveBounds();

  void _scheduleSaveBounds() {
    _saveBoundsTimer?.cancel();
    _saveBoundsTimer = Timer(
      const Duration(milliseconds: 800),
      _saveWindowBounds,
    );
  }

  Future<void> _saveWindowBounds() async {
    try {
      final b = await windowManager.getBounds();
      final service = getIt<SettingsService>();
      await service.save(
        service.settings.copyWith(
          windowX: b.left,
          windowY: b.top,
          windowWidth: b.width,
          windowHeight: b.height,
        ),
      );
    } catch (_) {}
  }

  Future<void> _destroyTray() async {
    try {
      await trayManager.destroy();
    } catch (_) {
      // No tray on this desktop; nothing to take down.
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
        await _windowCloser.exit();
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
            title: AppInfo.name,
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            // Above the navigator, so the resize edges also cover dialogs and
            // flyouts — on Linux the window has no frame of its own to grab.
            builder: (context, child) =>
                WindowResizeFrame(child: child ?? const SizedBox.shrink()),
            home: AppShell(onExit: _windowCloser.exit),
          );
        },
      ),
    );
  }
}
