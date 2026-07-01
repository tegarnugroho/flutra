import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/settings/theme_cubit.dart';
import '../../core/di/injection.dart';
import '../dashboard/dashboard_page.dart';
import '../emulator/emulator_manager_page.dart';
import '../sdk/license_manager_page.dart';
import '../sdk/sdk_manager_page.dart';
import 'placeholder_page.dart';

/// Root navigation shell using a Fluent [NavigationView] side pane.
///
/// Only the Dashboard is fully implemented in this milestone; the remaining
/// destinations render a [PlaceholderPage] so the full IA is navigable.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      titleBar: const _TitleBar(),
      pane: NavigationPane(
        selected: _index,
        onChanged: (i) => setState(() => _index = i),
        displayMode: PaneDisplayMode.auto,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.view_dashboard),
            title: const Text('Dashboard'),
            body: const DashboardPage(),
          ),
          PaneItemHeader(header: const Text('SDK')),
          _placeholder(FluentIcons.download, 'SDK Installer'),
          PaneItem(
            icon: const Icon(FluentIcons.packages),
            title: const Text('SDK Manager'),
            body: const SdkManagerPage(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.permissions),
            title: const Text('License Manager'),
            body: const LicenseManagerPage(),
          ),
          _placeholder(FluentIcons.build_queue_new, 'Package Downloader'),
          _placeholder(FluentIcons.sync, 'Updates'),
          PaneItemHeader(header: const Text('Emulators')),
          PaneItem(
            icon: const Icon(FluentIcons.cell_phone),
            title: const Text('Emulator Manager'),
            body: const EmulatorManagerPage(),
          ),
          _placeholder(FluentIcons.command_prompt, 'Emulator Console'),
          PaneItemHeader(header: const Text('Devices')),
          _placeholder(FluentIcons.plug_connected, 'Device Manager'),
          _placeholder(FluentIcons.text_document, 'Logcat Viewer'),
          _placeholder(FluentIcons.installation, 'APK Installer'),
          PaneItemHeader(header: const Text('Environment')),
          _placeholder(FluentIcons.health, 'Flutter Doctor'),
        ],
        footerItems: [
          _placeholder(FluentIcons.settings, 'Settings'),
        ],
      ),
    );
  }

  PaneItem _placeholder(IconData icon, String title) => PaneItem(
        icon: Icon(icon),
        title: Text(title),
        body: PlaceholderPage(title: title, icon: icon),
      );
}

/// Custom title bar shown at the top of the [NavigationView].
class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      child: Row(
        children: [
          Icon(FluentIcons.cell_phone, size: 18, color: theme.accentColor),
          const SizedBox(width: 8),
          Text('Android SDK Manager', style: theme.typography.bodyStrong),
          const Spacer(),
          const _ThemeToggle(),
        ],
      ),
    );
  }
}

/// Light/dark toggle wired to the [ThemeCubit].
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeMode>(
      bloc: getIt<ThemeCubit>(),
      builder: (context, mode) {
        final isDark = mode == ThemeMode.dark;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ToggleButton(
            checked: isDark,
            onChanged: (_) => getIt<ThemeCubit>().toggle(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isDark ? FluentIcons.clear_night : FluentIcons.sunny,
                    size: 16),
                const SizedBox(width: 6),
                Text(isDark ? 'Dark' : 'Light'),
              ],
            ),
          ),
        );
      },
    );
  }
}
