import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/device.dart';

/// Callbacks for the actions a [DeviceCard] can trigger.
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

/// A card describing one connected device with its actions.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.busy,
    required this.actions,
  });

  final Device device;
  final bool busy;
  final DeviceActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final online = device.state.isOnline;

    return Card(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _icon(theme),
          const SizedBox(width: 14),
          Expanded(child: _info(theme)),
          const SizedBox(width: 12),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 20, height: 20, child: ProgressRing(strokeWidth: 2)),
            )
          else if (device.supportsAdb)
            _actions(context, online)
          else
            _readOnlyBadge(theme),
        ],
      ),
    );
  }

  Widget _icon(FluentThemeData theme) {
    final color =
        device.state.isOnline ? const Color(0xFF3DDC84) : const Color(0xFF767676);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_iconData(), size: 22, color: color),
    );
  }

  IconData _iconData() {
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

  Widget _info(FluentThemeData theme) {
    final chips = <Widget>[
      _StatePill(state: device.state),
      if (!device.supportsAdb && device.platformLabel != null)
        _chip(theme, device.platformLabel!),
      if (device.androidRelease != null)
        _chip(theme, 'Android ${device.androidRelease}'),
      if (device.sdkInt != null) _chip(theme, 'API ${device.sdkInt}'),
      if (device.isEmulator) _chip(theme, 'Emulator'),
      if (device.batteryLevel != null) _battery(device.batteryLevel!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(device.displayName,
            style: theme.typography.bodyStrong,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(
          '${device.serial}${device.manufacturer != null ? ' • ${device.manufacturer}' : ''}',
          style: theme.typography.caption?.copyWith(
            color: theme.resources.textFillColorTertiary,
            fontFamily: 'Consolas',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    );
  }

  Widget _chip(FluentThemeData theme, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.resources.subtleFillColorSecondary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: theme.typography.caption),
      );

  Widget _battery(int level) {
    final color = level <= 15
        ? const Color(0xFFE81123)
        : level <= 40
            ? const Color(0xFFFFB900)
            : const Color(0xFF3DDC84);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.power_button, size: 11, color: color),
          const SizedBox(width: 4),
          Text('$level%',
              style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  /// Shown for non-adb Flutter targets (desktop/web) that have no adb actions.
  Widget _readOnlyBadge(FluentThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        'Flutter target',
        style: theme.typography.caption?.copyWith(
          color: theme.resources.textFillColorTertiary,
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, bool online) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (online)
          Tooltip(
            message: 'Open shell',
            child: IconButton(
              icon: const Icon(FluentIcons.command_prompt),
              onPressed: actions.onShell,
            ),
          ),
        if (online)
          Tooltip(
            message: 'Screenshot',
            child: IconButton(
              icon: const Icon(FluentIcons.camera),
              onPressed: actions.onScreenshot,
            ),
          ),
        const SizedBox(width: 4),
        DropDownButton(
          title: const Icon(FluentIcons.more, size: 14),
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.installation),
              text: const Text('Install APK'),
              onPressed: online ? actions.onInstallApk : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.text_document),
              text: const Text('Logcat'),
              onPressed: online ? actions.onLogcat : null,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.reset_device),
              text: const Text('Reboot'),
              onPressed:
                  online ? () => actions.onReboot(RebootTarget.system) : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.developer_tools),
              text: const Text('Reboot to bootloader'),
              onPressed: online
                  ? () => actions.onReboot(RebootTarget.bootloader)
                  : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.power_button),
              text: const Text('Reboot to recovery'),
              onPressed:
                  online ? () => actions.onReboot(RebootTarget.recovery) : null,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.plug_disconnected,
                  color: Color(0xFFC42B1C)),
              text: Text(device.isEmulator ? 'Stop emulator' : 'Disconnect',
                  style: const TextStyle(color: Color(0xFFC42B1C))),
              onPressed: actions.onDisconnect,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});

  final DeviceState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      DeviceState.device => const Color(0xFF3DDC84),
      DeviceState.unauthorized => const Color(0xFFFFB900),
      DeviceState.offline => const Color(0xFF767676),
      _ => const Color(0xFFE81123),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(state.label,
              style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
