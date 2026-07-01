import 'package:fluent_ui/fluent_ui.dart';

import '../dashboard/dashboard_page.dart';
import '../device/device_manager_page.dart';
import '../doctor/flutter_doctor_page.dart';
import '../emulator/emulator_manager_page.dart';
import '../flutter_sdk/flutter_sdk_page.dart';
import '../logcat/logcat_viewer_page.dart';
import '../sdk/license_manager_page.dart';
import '../sdk/sdk_manager_page.dart';
import '../sdk/updates_page.dart';
import '../settings/settings_page.dart';

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
          PaneItemExpander(
            icon: const Icon(FluentIcons.cell_phone),
            title: const Text('Android'),
            initiallyExpanded: true,
            items: [
              PaneItem(
                icon: const Icon(FluentIcons.packages),
                title: const Text('SDK Manager'),
                body: const SdkManagerPage(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.cell_phone),
                title: const Text('Virtual Device Manager'),
                body: const EmulatorManagerPage(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.permissions),
                title: const Text('License Manager'),
                body: const LicenseManagerPage(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.text_document),
                title: const Text('Logcat'),
                body: const LogcatViewerPage(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.sync),
                title: const Text('Updates'),
                body: const UpdatesPage(),
              ),
            ],
          ),
          PaneItemExpander(
            icon: const Icon(FluentIcons.developer_tools),
            title: const Text('Flutter'),
            initiallyExpanded: true,
            items: [
              PaneItem(
                icon: const Icon(FluentIcons.developer_tools),
                title: const Text('Flutter SDK'),
                body: const FlutterSdkPage(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.health),
                title: const Text('Flutter Doctor'),
                body: const FlutterDoctorPage(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.plug_connected),
                title: const Text('Device Manager'),
                body: const DeviceManagerPage(),
              ),
            ],
          ),
        ],
        footerItems: [
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
            body: const SettingsPage(),
          ),
        ],
      ),
    );
  }

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
          Text('Flutter SDK Manager', style: theme.typography.bodyStrong),
        ],
      ),
    );
  }
}
