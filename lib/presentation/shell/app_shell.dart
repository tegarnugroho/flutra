import 'package:fluent_ui/fluent_ui.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// fluent_ui exports a FluentIcons of its own (the older MDL2 set), so the
// system icons — the rounded outline family the sidebar is drawn in — need a
// prefix to sit alongside it.
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as sys;
// One brand glyph the Fluent set has no equivalent for: the Flutter logo the
// mockup puts beside the Flutter section.
import 'package:simple_icons/simple_icons.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/settings/app_settings.dart';
import '../../application/shell/shell_navigator.dart';
import '../../application/settings/settings_cubit.dart';
import '../../core/di/injection.dart';
import '../dashboard/dashboard_page.dart';
import '../device/device_manager_page.dart';
import '../doctor/flutter_doctor_page.dart';
import '../emulator/emulator_manager_page.dart';
import '../flutter_sdk/flutter_sdk_page.dart';
import '../logcat/logcat_viewer_page.dart';
import '../sdk/license_manager_page.dart';
import '../sdk/sdk_manager_page.dart';
import '../sdk/updates_page.dart';
import '../settings/settings_page.dart' show SettingsPage;
import '../window/task_windows.dart';
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
    required this.id,
    required this.icon,
    required this.label,
    required this.body,
    this.group,
    this.inFooter = false,
  });

  /// Stable name other screens navigate by, so the pane's index space stays
  /// this file's business.
  final ShellDestination id;

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
      id: ShellDestination.dashboard,
      icon: sys.FluentIcons.grid_24_regular,
      label: 'Dashboard',
      body: DashboardPage(),
    ),
    _Destination(
      id: ShellDestination.sdkManager,
      icon: sys.FluentIcons.layer_24_regular,
      label: 'SDK manager',
      body: SdkManagerPage(),
      group: 'Android',
    ),
    _Destination(
      id: ShellDestination.virtualDevices,
      icon: sys.FluentIcons.phone_24_regular,
      label: 'Virtual devices',
      body: EmulatorManagerPage(),
    ),
    _Destination(
      id: ShellDestination.licenses,
      icon: sys.FluentIcons.document_ribbon_24_regular,
      label: 'Licenses',
      body: LicenseManagerPage(),
    ),
    _Destination(
      id: ShellDestination.logcat,
      icon: sys.FluentIcons.document_bullet_list_24_regular,
      label: 'Logcat',
      body: LogcatViewerPage(),
    ),
    _Destination(
      id: ShellDestination.updates,
      icon: sys.FluentIcons.arrow_sync_24_regular,
      label: 'Updates',
      body: UpdatesPage(),
    ),
    _Destination(
      id: ShellDestination.flutterSdk,
      icon: SimpleIcons.flutter,
      label: 'Flutter SDK',
      body: FlutterSdkPage(),
      group: 'Flutter',
    ),
    _Destination(
      id: ShellDestination.flutterDoctor,
      icon: sys.FluentIcons.heart_pulse_24_regular,
      label: 'Flutter doctor',
      body: FlutterDoctorPage(),
    ),
    _Destination(
      id: ShellDestination.devices,
      icon: sys.FluentIcons.plug_connected_24_regular,
      label: 'Devices',
      body: DeviceManagerPage(),
    ),
    _Destination(
      id: ShellDestination.settings,
      icon: sys.FluentIcons.settings_24_regular,
      label: 'Settings',
      body: SettingsPage(),
      inFooter: true,
    ),
  ];

  /// Pane index of the Settings destination, for the app menu's shortcut to it.
  static final int _settingsIndex = _destinations.indexWhere(
    (d) => d.label == 'Settings',
  );

  /// Below this the pane's 200px costs more than the content can spare.
  static const double _railBreakpoint = 880;

  /// Pane width tween, shared by the indicator so the accent bar tracks it.
  static const Duration _paneDuration = Duration(milliseconds: 180);
  static const Curve _paneCurve = Curves.easeOutCubic;

  int _index = 0;
  bool _paletteOpen = false;

  final _menuController = FlyoutController();

  /// Visited destinations, oldest first. [_forward] holds what a back step
  /// undid and is dropped as soon as a new destination is chosen.
  final List<int> _back = [];
  final List<int> _forward = [];

  StreamSubscription<ShellNavigationRequest>? _navigation;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _navigation = getIt<ShellNavigator>().onNavigate.listen(_onNavigate);
  }

  /// Another screen asked to be shown. Routed through the same [_go] the pane
  /// uses, so the back/forward history records it too.
  void _onNavigate(ShellNavigationRequest request) {
    final index = _destinations.indexWhere((d) => d.id == request.destination);
    if (index < 0) return;
    // The autoRun flag rides on the navigator itself — the destination claims
    // it as it builds, which is after this runs.
    _go(index);
  }

  @override
  void dispose() {
    _navigation?.cancel();
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
            leading: const Icon(WindowsIcons.info),
            text: const Text('About Flutter SDK Manager'),
            onPressed: openAboutWindow,
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
  static PaneItem _item(_Destination destination, AppPalette palette) {
    return PaneItem(
      icon: Icon(destination.icon, size: 16),
      title: Text(destination.label),
      selectedTileColor: WidgetStateProperty.all(palette.surfaceRaised),
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
      // A Builder both resolves the theme (this factory is static) and reads
      // the live display mode, so the same adapter is the group's caption in
      // the open pane and a plain rule on the rail.
      child: Builder(
        builder: (context) {
          final palette = AppPalette.of(context);
          final rail =
              NavigationView.dataOf(context).displayMode ==
              PaneDisplayMode.compact;
          // 52px of rail cannot hold "ANDROID" — it wrapped to "Andr oid".
          // A divider says the same thing in the space available.
          if (rail) {
            return Container(
              height: 24,
              alignment: Alignment.center,
              child: Container(
                height: AppShape.hairline,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: palette.border,
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 4),
            child: Text(text, style: AppTextStyles.of(context).sectionLabel),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The collapse choice is a persisted preference, so the shell rebuilds
    // with it rather than holding a copy that would drift on restart.
    return BlocProvider.value(
      // The singleton, shared with the Settings page — .value so neither owner
      // closes it.
      value: getIt<SettingsCubit>(),
      child: BlocBuilder<SettingsCubit, AppSettings>(
        buildWhen: (p, c) => p.sidebarCollapsed != c.sidebarCollapsed,
        builder: (context, settings) => LayoutBuilder(
          builder: (context, constraints) => _build(
            context,
            collapsed: settings.sidebarCollapsed,
            railMode:
                settings.sidebarCollapsed ||
                constraints.maxWidth < _railBreakpoint,
          ),
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context, {
    required bool collapsed,
    required bool railMode,
  }) {
    final palette = AppPalette.of(context);
    final items = <NavigationPaneItem>[];
    for (final destination in _destinations.where((d) => !d.inFooter)) {
      if (destination.group != null) {
        items.add(_sectionLabel(destination.group!));
      }
      items.add(_item(destination, palette));
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
        actions: _titleBarActions(collapsed),
      ),
      // Hairline outline around the content area — this is what draws the
      // divider between the sidebar and the page.
      contentShape: RoundedRectangleBorder(
        side: BorderSide(color: palette.border, width: AppShape.hairline),
      ),
      // Fade, not fluent's default entrance slide.
      //
      // That default is `EntrancePageTransition(vertical: true, startFrom:
      // 0.25)`: the incoming page starts a quarter of the window below where
      // it belongs and rises into place. On a page that opens on a skeleton
      // there is nothing to read during the slide, so the only thing the
      // motion communicates is that the layout is wrong — the title and the
      // placeholders sit low and drift up. A fade changes nothing about where
      // anything is.
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      pane: NavigationPane(
        selected: _index,
        onChanged: _go,
        // Rail when the user pinned it, or when the window is too narrow to
        // spare 200px. The narrow rule never overwrites the user's choice, so
        // widening restores what they picked.
        displayMode: railMode ? PaneDisplayMode.compact : PaneDisplayMode.auto,
        // compactWidth is 2px over fluent's 50 default on purpose. A pane item
        // lays out at compactWidth minus its 12px margin, and while the pane
        // animates between compact and open it is briefly measured with the
        // *open* item layout: 24px of icon padding around a 15px icon needs
        // 39px, one more than 50 leaves. 52 removes the 1px overflow.
        size: const NavigationPaneSize(openWidth: 190, compactWidth: 52),
        // Accent bar at the pane's leading edge, in both modes.
        indicator: StickyNavigationIndicator(
          color: palette.accent,
          indicatorSize: 2.5,
          curve: _paneCurve,
          duration: _paneDuration,
        ),
        items: items,
        footerItems: [
          PaneItemSeparator(
            color: palette.border,
            thickness: AppShape.hairline,
          ),
          for (final destination in _destinations.where((d) => d.inFooter))
            _item(destination, palette),
        ],
      ),
    );
  }

  List<Widget> _titleBarActions(bool collapsed) {
    return [
      // Segoe chrome glyphs throughout, so the shell controls read as one set
      // with the caption buttons rather than two icon families side by side.
      TitleBarActionButton(
        icon: WindowsIcons.dock_left,
        tooltip: collapsed ? 'Show sidebar' : 'Hide sidebar',
        isActive: collapsed,
        onPressed: () => getIt<SettingsCubit>().setSidebarCollapsed(!collapsed),
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
