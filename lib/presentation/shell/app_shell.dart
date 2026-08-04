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
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Root navigation shell using a Fluent [NavigationView] side pane.
///
/// The groups are always expanded, so they are plain section labels rather than
/// expanders — no chevrons. Item colours and text styles come from the
/// navigation pane theme in `AppTheme`.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// A nav destination: 15px icon, 12px sentence-case label, raised tile when
  /// active.
  static PaneItem _item(IconData icon, String label, Widget body) {
    return PaneItem(
      icon: Icon(icon, size: 15),
      title: Text(label),
      selectedTileColor: WidgetStateProperty.all(AppColors.surfaceRaised),
      body: body,
    );
  }

  /// A group label ("Android", "Flutter").
  ///
  /// [PaneItemHeader] is not an option: fluent_ui 4.16 renders it as an empty
  /// [SizedBox] in the open pane, so the label is drawn through a widget
  /// adapter instead.
  static PaneItemWidgetAdapter _sectionLabel(String text) {
    return PaneItemWidgetAdapter(
      applyPadding: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 4),
        child: Text(text, style: AppTextStyles.sectionLabel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      titleBar: const _TitleBar(),
      // Hairline outline around the content area — this is what draws the
      // divider between the sidebar and the page.
      contentShape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border, width: AppShape.hairline),
      ),
      pane: NavigationPane(
        selected: _index,
        onChanged: (i) => setState(() => _index = i),
        displayMode: PaneDisplayMode.auto,
        size: const NavigationPaneSize(openWidth: 190),
        // The active item is marked by its raised tile, not an accent bar.
        indicator: null,
        items: [
          _item(FluentIcons.view_dashboard, 'Dashboard', const DashboardPage()),
          _sectionLabel('Android'),
          _item(FluentIcons.packages, 'SDK manager', const SdkManagerPage()),
          _item(FluentIcons.cell_phone, 'Virtual devices',
              const EmulatorManagerPage()),
          _item(FluentIcons.permissions, 'Licenses',
              const LicenseManagerPage()),
          _item(FluentIcons.text_document, 'Logcat',
              const LogcatViewerPage()),
          _item(FluentIcons.sync, 'Updates', const UpdatesPage()),
          _sectionLabel('Flutter'),
          _item(FluentIcons.developer_tools, 'Flutter SDK',
              const FlutterSdkPage()),
          _item(FluentIcons.health, 'Flutter doctor',
              const FlutterDoctorPage()),
          _item(FluentIcons.plug_connected, 'Devices',
              const DeviceManagerPage()),
        ],
        footerItems: [
          PaneItemSeparator(
            color: AppColors.border,
            thickness: AppShape.hairline,
          ),
          _item(FluentIcons.settings, 'Settings', const SettingsPage()),
        ],
      ),
    );
  }
}

/// Custom title bar drawn at the top of the [NavigationView].
///
/// It shares the sidebar surface so the two read as one chrome band. The OS
/// window frame around it is native (`WS_OVERLAPPEDWINDOW` + DWM dark mode) and
/// is left untouched.
class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 40,
      color: palette.sidebarBg,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(FluentIcons.cell_phone, size: 15, color: palette.textSecondary),
          const SizedBox(width: 8),
          const Text('Flutter SDK Manager', style: AppTextStyles.titleBar),
        ],
      ),
    );
  }
}
