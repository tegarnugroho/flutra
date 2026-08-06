import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/device/device_manager_cubit.dart';
import '../../../domain/entities/device.dart';
import '../../common/app_badge.dart';
import '../../common/copy_icon_button.dart';
import '../../common/outlined_action_button.dart';
import '../../common/status_pill.dart';
import '../../common/tile_box.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Callbacks for the actions a [DeviceTile] can trigger.
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

/// One connected device: what it is, whether adb can reach it, and the actions
/// worth a button.
///
/// Shell and Screenshot sit on the tile rather than behind hover, so the two
/// things a device is opened for are visible without finding them first.
class DeviceTile extends StatefulWidget {
  const DeviceTile({
    super.key,
    required this.device,
    required this.task,
    required this.actions,
  });

  final Device device;

  /// The action in flight for this device, or null when it is idle.
  final DeviceTask? task;

  final DeviceActions actions;

  @override
  State<DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<DeviceTile> {
  final _menu = FlyoutController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  bool get _busy => widget.task != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final device = widget.device;
    final online = device.state.isOnline;

    return TileBox(
      emphasised: online,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _DeviceMark(device: device, online: online),
            const SizedBox(width: 12),
            Expanded(child: _identity(context, palette)),
            const SizedBox(width: 12),
            if (!device.supportsAdb)
              // Nothing adb can do with a browser or the host desktop; the
              // badge says why the buttons are missing.
              const AppBadge('Flutter target')
            else ...[
              ..._actions(online),
              const SizedBox(width: 6),
              FlyoutTarget(
                controller: _menu,
                child: OutlinedActionButton(
                  icon: FluentIcons.more,
                  dense: true,
                  tooltip: 'More actions',
                  onPressed: () => _showMenu(context, online),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(bool online) {
    final task = widget.task;
    if (task != null) {
      return [
        OutlinedActionButton(
          icon: FluentIcons.camera,
          label: task.label,
          dense: true,
          busy: true,
          // Disabled: adb is mid-command and a second one would queue behind
          // it with no way to tell which finished.
          onPressed: null,
        ),
      ];
    }
    if (!online) return const [];
    return [
      OutlinedActionButton(
        icon: FluentIcons.command_prompt,
        label: 'Shell',
        dense: true,
        tooltip: 'Open an adb shell',
        onPressed: widget.actions.onShell,
      ),
      const SizedBox(width: 6),
      OutlinedActionButton(
        icon: FluentIcons.camera,
        dense: true,
        tooltip: 'Screenshot',
        onPressed: widget.actions.onScreenshot,
      ),
    ];
  }

  Widget _identity(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    final device = widget.device;
    final pill = _statePill(device.state, palette);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                device.displayName,
                style: text.rowTitle.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Online is the normal state and says nothing; the pill is spent
            // on the states that stop a device being usable.
            if (pill != null) ...[const SizedBox(width: 8), pill],
          ],
        ),
        const SizedBox(height: 3),
        _MetaLine(device: device),
      ],
    );
  }

  /// The pill for a device that is not simply online, or null when it is.
  StatusPill? _statePill(DeviceState state, AppPalette palette) {
    return switch (state) {
      DeviceState.device => null,
      DeviceState.offline => StatusPill(
        label: 'offline',
        foreground: palette.textMuted,
        background: palette.surfaceRaised,
      ),
      DeviceState.unauthorized || DeviceState.bootloader => StatusPill(
        label: state.label.toLowerCase(),
        foreground: palette.statusWarn,
        background: palette.warnSurface,
      ),
      _ => StatusPill(
        label: state.label.toLowerCase(),
        foreground: palette.statusError,
        background: palette.dangerSurface,
      ),
    };
  }

  void _showMenu(BuildContext context, bool online) {
    final palette = AppPalette.of(context);
    final actions = widget.actions;
    final device = widget.device;
    _menu.showFlyout(
      builder: (flyoutContext) {
        void run(VoidCallback action) {
          Navigator.of(flyoutContext).pop();
          action();
        }

        final enabled = online && !_busy;
        return MenuFlyout(
          items: [
            // What you push to the device, and what you read back from it.
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.installation, size: 14),
              text: const Text('Install APK'),
              onPressed: enabled ? () => run(actions.onInstallApk) : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.text_document, size: 14),
              text: const Text('Logcat'),
              onPressed: enabled ? () => run(actions.onLogcat) : null,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.reset_device, size: 14),
              text: const Text('Reboot'),
              onPressed: enabled
                  ? () => run(() => actions.onReboot(RebootTarget.system))
                  : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.developer_tools, size: 14),
              text: const Text('Reboot to bootloader'),
              onPressed: enabled
                  ? () => run(() => actions.onReboot(RebootTarget.bootloader))
                  : null,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.power_button, size: 14),
              text: const Text('Reboot to recovery'),
              onPressed: enabled
                  ? () => run(() => actions.onReboot(RebootTarget.recovery))
                  : null,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: Icon(
                FluentIcons.plug_disconnected,
                size: 14,
                color: _busy ? null : palette.statusError,
              ),
              text: Text(
                device.isEmulator ? 'Stop emulator' : 'Disconnect',
                style: _busy ? null : TextStyle(color: palette.statusError),
              ),
              // Reachable while offline: an unresponsive device is exactly the
              // one you want to drop.
              onPressed: _busy ? null : () => run(actions.onDisconnect),
            ),
          ],
        );
      },
    );
  }
}

/// The transport icon in its rounded square.
class _DeviceMark extends StatelessWidget {
  const _DeviceMark({required this.device, required this.online});

  final Device device;
  final bool online;

  static IconData iconFor(Device device) {
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: online ? palette.okSurface : palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Icon(
        iconFor(device),
        size: 15,
        color: online ? palette.statusOk : palette.textSecondary,
      ),
    );
  }
}

/// `emulator-5554 ⧉ · Google · Android 14 (API 34) · battery 100%`.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.device});

  final Device device;

  /// Past this the serial ellipsizes rather than pushing the rest off the tile
  /// — a network serial is long and its tail is the least useful part.
  static const _maxSerialWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final rest = _fragments(device).join(' · ');

    return Row(
      children: [
        // The serial is what every adb command needs, so it leads the line and
        // carries the copy action.
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxSerialWidth),
            child: Text(
              device.serial,
              style: text.monoMeta.copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 4),
        CopyIconButton(value: device.serial, label: 'Serial'),
        if (rest.isNotEmpty)
          // One run of text rather than a widget each: the whole tail is the
          // first thing that should give when the window narrows.
          Expanded(
            child: Text(
              ' · $rest',
              style: text.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// The plain-language half of the meta line, in the order it reads.
  static List<String> _fragments(Device device) {
    final platform = _platform(device);
    return <String>[
      if (!device.supportsAdb && device.platformLabel != null)
        device.platformLabel!,
      if (device.manufacturer != null) device.manufacturer!,
      ?platform,
      if (device.isEmulator) 'emulator',
      if (device.batteryLevel != null) 'battery ${device.batteryLevel}%',
    ];
  }

  /// `Android 14 (API 34)`, or whichever half of it adb reported.
  static String? _platform(Device device) {
    final release = device.androidRelease;
    final sdk = device.sdkInt;
    if (release != null && sdk != null) return 'Android $release (API $sdk)';
    if (release != null) return 'Android $release';
    if (sdk != null) return 'API $sdk';
    return null;
  }
}
