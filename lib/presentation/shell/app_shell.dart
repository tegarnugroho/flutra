import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../dashboard/dashboard_page.dart';
import '../device/device_manager_page.dart';
import '../doctor/flutter_doctor_page.dart';
import '../emulator/emulator_manager_page.dart';
import '../flutter_sdk/flutter_sdk_page.dart';
import '../logcat/logcat_viewer_page.dart';
import '../sdk/license_manager_page.dart';
import '../sdk/sdk_manager_page.dart';
import '../sdk/updates_page.dart';
import '../settings/settings_page.dart' show SettingsPage, openDevLogsWindow;
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'command_palette.dart';
import 'custom_title_bar.dart';

/// A navigable page in the shell.
///
/// The order of [_AppShellState._destinations] *is* the index space of
/// [NavigationPane.selected]: fluent counts only navigable [PaneItem]s, so the
/// section labels and the footer separator don't shift it. Footer entries must
/// therefore stay last in the list, matching `items + footerItems`.
class _Destination {
  const _Destination({
    required this.icon,
    required this.label,
    required this.body,
    this.group,
    this.inFooter = false,
  });

  final IconData icon;
  final String label;
  final Widget body;

  /// Section label drawn immediately above this item in the pane.
  final String? group;

  /// Rendered in the pane footer instead of the main list.
  final bool inFooter;
}

/// Root navigation shell using a Fluent [NavigationView] side pane.
///
/// The groups are always expanded, so they are plain section labels rather than
/// expanders — no chevrons. Item colours and text styles come from the
/// navigation pane theme in `AppTheme`.
///
/// The shell also owns the title bar controls: sidebar collapse, the jump-to-
/// page palette, and the back/forward history.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _destinations = <_Destination>[
    _Destination(
      icon: FluentIcons.view_dashboard,
      label: 'Dashboard',
      body: DashboardPage(),
    ),
    _Destination(
      icon: FluentIcons.packages,
      label: 'SDK manager',
      body: SdkManagerPage(),
      group: 'Android',
    ),
    _Destination(
      icon: FluentIcons.cell_phone,
      label: 'Virtual devices',
      body: EmulatorManagerPage(),
    ),
    _Destination(
      icon: FluentIcons.permissions,
      label: 'Licenses',
      body: LicenseManagerPage(),
    ),
    _Destination(
      icon: FluentIcons.text_document,
      label: 'Logcat',
      body: LogcatViewerPage(),
    ),
    _Destination(
      icon: FluentIcons.sync,
      label: 'Updates',
      body: UpdatesPage(),
    ),
    _Destination(
      icon: FluentIcons.developer_tools,
      label: 'Flutter SDK',
      body: FlutterSdkPage(),
      group: 'Flutter',
    ),
    _Destination(
      icon: FluentIcons.health,
      label: 'Flutter doctor',
      body: FlutterDoctorPage(),
    ),
    _Destination(
      icon: FluentIcons.plug_connected,
      label: 'Devices',
      body: DeviceManagerPage(),
    ),
    _Destination(
      icon: FluentIcons.settings,
      label: 'Settings',
      body: SettingsPage(),
      inFooter: true,
    ),
  ];

  /// Pane index of the Settings destination, for the app menu's shortcut to it.
  static final int _settingsIndex =
      _destinations.indexWhere((d) => d.label == 'Settings');

  int _index = 0;
  bool _paneCollapsed = false;
  bool _paletteOpen = false;

  final _menuController = FlyoutController();

  /// Visited destinations, oldest first. [_forward] holds what a back step
  /// undid and is dropped as soon as a new destination is chosen.
  final List<int> _back = [];
  final List<int> _forward = [];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _menuController.dispose();
    super.dispose();
  }

  /// The app menu behind the hamburger, anchored under the button.
  void _showMenu() {
    _menuController.showFlyout(
      placementMode: FlyoutPlacementMode.bottomLeft,
      builder: (context) => MenuFlyout(
        items: [
          MenuFlyoutItem(
            leading: const Icon(WindowsIcons.settings),
            text: const Text('Settings'),
            onPressed: () => _go(_settingsIndex),
          ),
          MenuFlyoutItem(
            leading: const Icon(WindowsIcons.developer_tools),
            text: const Text('Developer logs'),
            onPressed: openDevLogsWindow,
          ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            leading: const Icon(WindowsIcons.power_button),
            text: const Text('Exit'),
            onPressed: _exit,
          ),
        ],
      ),
    );
  }

  /// Quits for real, unlike the close button — that one honours the
  /// "close to tray" preference handled in `AndroidSdkManagerApp`.
  Future<void> _exit() async {
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.destroy();
  }

  /// Ctrl+K opens the palette from anywhere, including while a page's own text
  /// field has focus — hence a global handler rather than a [Shortcuts] scope.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    _openPalette();
    return true;
  }

  /// Navigates to [index] and records the jump in the history.
  void _go(int index) {
    if (index == _index) return;
    setState(() {
      _back.add(_index);
      _forward.clear();
      _index = index;
    });
  }

  void _goBack() {
    if (_back.isEmpty) return;
    setState(() {
      _forward.add(_index);
      _index = _back.removeLast();
    });
  }

  void _goForward() {
    if (_forward.isEmpty) return;
    setState(() {
      _back.add(_index);
      _index = _forward.removeLast();
    });
  }

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    setState(() => _paletteOpen = true);
    final target = await showCommandPalette(
      context,
      entries: [
        for (var i = 0; i < _destinations.length; i++)
          PaletteEntry(
            index: i,
            icon: _destinations[i].icon,
            label: _destinations[i].label,
            group: _groupOf(i),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _paletteOpen = false);
    if (target != null) _go(target);
  }

  /// The section a destination belongs to — the nearest [_Destination.group]
  /// at or above it, since a group label applies until the next one. Footer
  /// destinations sit below the separator and belong to no section.
  static String? _groupOf(int index) {
    if (_destinations[index].inFooter) return null;
    for (var i = index; i >= 0; i--) {
      if (_destinations[i].group != null) return _destinations[i].group;
    }
    return null;
  }

  /// A nav destination: 15px icon, 12px sentence-case label, raised tile when
  /// active.
  static PaneItem _item(_Destination destination) {
    return PaneItem(
      icon: Icon(destination.icon, size: 15),
      title: Text(destination.label),
      selectedTileColor: WidgetStateProperty.all(AppColors.surfaceRaised),
      body: destination.body,
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
        child: Text(text, style: AppTextStyles.of(context).sectionLabel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <NavigationPaneItem>[];
    for (final destination in _destinations.where((d) => !d.inFooter)) {
      if (destination.group != null) {
        items.add(_sectionLabel(destination.group!));
      }
      items.add(_item(destination));
    }

    return NavigationView(
      titleBar: CustomTitleBar(
        // The app menu takes the app-icon slot, ahead of the name.
        leading: FlyoutTarget(
          controller: _menuController,
          child: TitleBarActionButton(
            icon: WindowsIcons.global_nav_button,
            tooltip: 'Menu',
            onPressed: _showMenu,
          ),
        ),
        actions: _titleBarActions(),
      ),
      // Hairline outline around the content area — this is what draws the
      // divider between the sidebar and the page.
      contentShape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border, width: AppShape.hairline),
      ),
      pane: NavigationPane(
        selected: _index,
        onChanged: _go,
        // Collapsing pins the pane to icons-only; expanded stays adaptive, so a
        // narrow window still falls back to compact on its own.
        displayMode:
            _paneCollapsed ? PaneDisplayMode.compact : PaneDisplayMode.auto,
        // compactWidth is 2px over fluent's 50 default on purpose. A pane item
        // lays out at compactWidth minus its 12px margin, and while the pane
        // animates between compact and open it is briefly measured with the
        // *open* item layout: 24px of icon padding around a 15px icon needs
        // 39px, one more than 50 leaves. 52 removes the 1px overflow.
        size: const NavigationPaneSize(openWidth: 190, compactWidth: 52),
        // The active item is marked by its raised tile, not an accent bar.
        indicator: null,
        items: items,
        footerItems: [
          PaneItemSeparator(
            color: AppColors.border,
            thickness: AppShape.hairline,
          ),
          for (final destination in _destinations.where((d) => d.inFooter))
            _item(destination),
        ],
      ),
    );
  }

  List<Widget> _titleBarActions() {
    return [
      // Segoe chrome glyphs throughout, so the shell controls read as one set
      // with the caption buttons rather than two icon families side by side.
      TitleBarActionButton(
        icon: WindowsIcons.dock_left,
        tooltip: _paneCollapsed ? 'Show sidebar' : 'Hide sidebar',
        isActive: _paneCollapsed,
        onPressed: () => setState(() => _paneCollapsed = !_paneCollapsed),
      ),
      TitleBarActionButton(
        icon: WindowsIcons.search,
        tooltip: 'Go to page (Ctrl+K)',
        onPressed: _openPalette,
      ),
      const SizedBox(width: 6),
      TitleBarActionButton(
        icon: WindowsIcons.back,
        tooltip: 'Back',
        onPressed: _back.isEmpty ? null : _goBack,
      ),
      TitleBarActionButton(
        icon: WindowsIcons.forward,
        tooltip: 'Forward',
        onPressed: _forward.isEmpty ? null : _goForward,
      ),
    ];
  }
}
