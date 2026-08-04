import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/device.dart';
import '../../common/copy_icon_button.dart';
import '../../common/grouped_list.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Callbacks for the actions a [DeviceRow] can trigger.
class DeviceActions {
  const DeviceActions({
    required this.onShell,
    required this.onScreenshot,
    required this.onInstallApk,
    required this.onLogcat,
    required this.onReboot,
    required this.onDisconnect,
  });

  final VoidCallback onShell;
  final VoidCallback onScreenshot;
  final VoidCallback onInstallApk;
  final VoidCallback onLogcat;
  final void Function(RebootTarget) onReboot;
  final VoidCallback onDisconnect;
}

/// One connected device: status dot, name with inline meta, mono serial and
/// hover-only actions.
class DeviceRow extends StatefulWidget {
  const DeviceRow({
    super.key,
    required this.device,
    required this.busy,
    required this.actions,
  });

  final Device device;
  final bool busy;
  final DeviceActions actions;

  @override
  State<DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends State<DeviceRow> {
  final _overflow = FlyoutController();

  @override
  void dispose() {
    _overflow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final device = widget.device;
    final online = device.state.isOnline;

    return GroupedListRow(
      statusColor: _statusColor(device.state, palette),
      showStatusSlot: true,
      icon: _iconData(),
      title: device.displayName,
      secondary: _meta().isEmpty ? null : _meta().join(' · '),
      trailing: [
        Text(device.serial, style: AppTextStyles.monoValue),
        CopyIconButton(value: device.serial, label: 'Serial'),
        if (widget.busy)
          const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
        else if (!device.supportsAdb)
          const Text('Flutter target', style: AppTextStyles.inlineNote),
      ],
      hoverActions: [
        if (!widget.busy && device.supportsAdb) ...[
          if (online)
            OutlinedActionButton(
              icon: FluentIcons.command_prompt,
              dense: true,
              tooltip: 'Open shell',
              onPressed: widget.actions.onShell,
            ),
          if (online)
            OutlinedActionButton(
              icon: FluentIcons.camera,
              dense: true,
              tooltip: 'Screenshot',
              onPressed: widget.actions.onScreenshot,
            ),
          FlyoutTarget(
            controller: _overflow,
            child: OutlinedActionButton(
              icon: FluentIcons.more,
              dense: true,
              tooltip: 'More actions',
              onPressed: () => _showOverflow(online),
            ),
          ),
        ],
      ],
    );
  }

  /// Inline metadata after the device name — platform, OS release, API level.
  List<String> _meta() {
    final device = widget.device;
    return <String>[
      if (!device.supportsAdb && device.platformLabel != null)
        device.platformLabel!,
      if (device.manufacturer != null) device.manufacturer!,
      if (device.androidRelease != null) 'Android ${device.androidRelease}',
      if (device.sdkInt != null) 'API ${device.sdkInt}',
      if (device.isEmulator) 'emulator',
      if (device.batteryLevel != null) 'battery ${device.batteryLevel}%',
      if (!device.state.isOnline) device.state.label,
    ];
  }

  static Color _statusColor(DeviceState state, AppPalette palette) =>
      switch (state) {
        DeviceState.device => palette.statusOk,
        DeviceState.unauthorized => palette.statusWarn,
        DeviceState.offline => palette.textMuted,
        _ => palette.statusError,
      };

  IconData _iconData() {
    final device = widget.device;
    if (!device.supportsAdb) {
      return switch (device.platformLabel) {
        'Web' => FluentIcons.globe,
        'Windows' || 'macOS' || 'Linux' => FluentIcons.screen,
        _ => FluentIcons.devices3,
      };
    }
    if (device.isEmulator) return FluentIcons.cell_phone;
    if (device.isNetwork) return FluentIcons.plug_connected;
    return FluentIcons.usb;
  }

  void _showOverflow(bool online) {
    final actions = widget.actions;
    _overflow.showFlyout(
      builder: (flyoutContext) {
        void run(VoidCallback action) {
          Navigator.of(flyoutContext).pop();
          action();
        }

        return MenuFlyout(
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.installation, size: 14),
              text: const Text('Install APK'),
              onPressed: online ? () => run(actions.onInstallApk) : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.text_document, size: 14),
              text: const Text('Logcat'),
              onPressed: online ? () => run(actions.onLogcat) : null,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.reset_device, size: 14),
              text: const Text('Reboot'),
              onPressed: online
                  ? () => run(() => actions.onReboot(RebootTarget.system))
                  : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.developer_tools, size: 14),
              text: const Text('Reboot to bootloader'),
              onPressed: online
                  ? () => run(() => actions.onReboot(RebootTarget.bootloader))
                  : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.power_button, size: 14),
              text: const Text('Reboot to recovery'),
              onPressed: online
                  ? () => run(() => actions.onReboot(RebootTarget.recovery))
                  : null,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.plug_disconnected,
                  size: 14, color: AppColors.statusError),
              text: Text(
                widget.device.isEmulator ? 'Stop emulator' : 'Disconnect',
                style: const TextStyle(color: AppColors.statusError),
              ),
              onPressed: () => run(actions.onDisconnect),
            ),
          ],
        );
      },
    );
  }
}
