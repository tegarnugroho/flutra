import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/settings/theme_cubit.dart';
import '../core/di/injection.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

/// Root widget: wires the Fluent theme to the [ThemeCubit] and hosts the shell.
class AndroidSdkManagerApp extends StatelessWidget {
  const AndroidSdkManagerApp({super.key});

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
