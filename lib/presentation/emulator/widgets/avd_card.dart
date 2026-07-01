import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/avd.dart';

/// A single AVD row with status and action controls.
class AvdCard extends StatelessWidget {
  const AvdCard({
    super.key,
    required this.avd,
    required this.busy,
    required this.onLaunch,
    required this.onColdBoot,
    required this.onStop,
    required this.onWipe,
    required this.onDelete,
    required this.onDuplicate,
    required this.onConsole,
  });

  final Avd avd;
  final bool busy;
  final VoidCallback onLaunch;
  final VoidCallback onColdBoot;
  final VoidCallback onStop;
  final VoidCallback onWipe;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onConsole;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Card(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _deviceIcon(theme),
          const SizedBox(width: 14),
          Expanded(child: _details(theme)),
          const SizedBox(width: 12),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 20, height: 20, child: ProgressRing(strokeWidth: 2)),
            )
          else
            _actions(context),
        ],
      ),
    );
  }

  Widget _deviceIcon(FluentThemeData theme) {
    final color = avd.isRunning ? const Color(0xFF3DDC84) : theme.accentColor;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        avd.deviceId?.contains('tv') == true
            ? FluentIcons.t_v_monitor
            : avd.deviceId?.contains('wear') == true
                ? FluentIcons.circle_ring
                : FluentIcons.cell_phone,
        size: 22,
        color: color,
      ),
    );
  }

  Widget _details(FluentThemeData theme) {
    final chips = <String>[
      if (avd.apiLevel != null) 'API ${avd.apiLevel}',
      if (avd.androidVersion != null) 'Android ${avd.androidVersion}',
      if (avd.tag != null) avd.tag!,
      if (avd.abi != null) avd.abi!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                avd.name,
                style: theme.typography.bodyStrong,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (avd.isRunning) ...[
              const SizedBox(width: 8),
              _runningBadge(),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          avd.deviceName ?? avd.deviceId ?? 'Unknown device',
          style: theme.typography.caption?.copyWith(
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final c in chips) _chip(theme, c)],
          ),
        ],
      ],
    );
  }

  Widget _runningBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF3DDC84).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.streaming, size: 10, color: Color(0xFF2A7345)),
            SizedBox(width: 4),
            Text('Running',
                style: TextStyle(fontSize: 11, color: Color(0xFF2A7345))),
          ],
        ),
      );

  Widget _chip(FluentThemeData theme, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.resources.subtleFillColorSecondary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: theme.typography.caption),
      );

  Widget _actions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (avd.isRunning)
          Tooltip(
            message: 'Stop',
            child: IconButton(
              icon: const Icon(FluentIcons.stop, color: Color(0xFFC42B1C)),
              onPressed: onStop,
            ),
          )
        else
          FilledButton(
            onPressed: onLaunch,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.play_solid, size: 12),
                SizedBox(width: 6),
                Text('Launch'),
              ],
            ),
          ),
        const SizedBox(width: 6),
        DropDownButton(
          title: const Icon(FluentIcons.more, size: 14),
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.a_a_d_logo),
              text: const Text('Cold boot'),
              onPressed: avd.isRunning ? null : onColdBoot,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.command_prompt),
              text: const Text('Emulator Console'),
              onPressed: onConsole,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.copy),
              text: const Text('Duplicate'),
              onPressed: onDuplicate,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.clear_selection),
              text: const Text('Wipe data'),
              onPressed: avd.isRunning ? null : onWipe,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.delete, color: Color(0xFFC42B1C)),
              text: const Text('Delete',
                  style: TextStyle(color: Color(0xFFC42B1C))),
              onPressed: avd.isRunning ? null : onDelete,
            ),
          ],
        ),
      ],
    );
  }
}
