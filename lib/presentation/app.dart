import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import '../application/emulator/emulator_events.dart';
import '../application/settings/theme_cubit.dart';
import '../core/di/injection.dart';
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
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    // A sub-window (e.g. Create Emulator) may have changed the AVD set.
    getIt<EmulatorEvents>().emitChanged();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: getIt<ThemeCubit>(),
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, mode) {
          return FluentApp(
            title: 'Android SDK Manager',
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
