import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/avd.dart';
import '../../common/app_loader.dart';
import '../../common/grouped_list.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';

/// One AVD: running dot, name with inline hardware meta, hover-only actions.
class AvdRow extends StatefulWidget {
  const AvdRow({
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
  State<AvdRow> createState() => _AvdRowState();
}

class _AvdRowState extends State<AvdRow> {
  final _overflow = FlyoutController();

  @override
  void dispose() {
    _overflow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final avd = widget.avd;

    return GroupedListRow(
      statusColor: avd.isRunning ? palette.statusOk : null,
      showStatusSlot: true,
      icon: _deviceIcon(avd),
      title: avd.name,
      secondary: _meta(avd).isEmpty ? null : _meta(avd).join(' · '),
      trailing: [if (widget.busy) AppLoader(size: AppLoaderSize.small)],
      hoverActions: [
        if (!widget.busy) ...[
          if (avd.isRunning)
            OutlinedActionButton(
              icon: FluentIcons.stop,
              label: 'Stop',
              dense: true,
              onPressed: widget.onStop,
            )
          else
            OutlinedActionButton(
              icon: FluentIcons.play_solid,
              label: 'Start',
              dense: true,
              onPressed: widget.onLaunch,
            ),
          FlyoutTarget(
            controller: _overflow,
            child: OutlinedActionButton(
              icon: FluentIcons.more,
              dense: true,
              tooltip: 'More actions',
              onPressed: _showOverflow,
            ),
          ),
        ],
      ],
    );
  }

  static List<String> _meta(Avd avd) => <String>[
    if (avd.deviceName != null || avd.deviceId != null)
      avd.deviceName ?? avd.deviceId!,
    if (avd.apiLevel != null) 'API ${avd.apiLevel}',
    if (avd.androidVersion != null) 'Android ${avd.androidVersion}',
    if (avd.tag != null) avd.tag!,
    if (avd.abi != null) avd.abi!,
  ];

  static IconData _deviceIcon(Avd avd) {
    if (avd.deviceId?.contains('tv') == true) return FluentIcons.t_v_monitor;
    if (avd.deviceId?.contains('wear') == true) return FluentIcons.circle_ring;
    return FluentIcons.cell_phone;
  }

  void _showOverflow() {
    final avd = widget.avd;
    _overflow.showFlyout(
      builder: (flyoutContext) {
        void run(VoidCallback action) {
          Navigator.of(flyoutContext).pop();
          action();
        }

        return MenuFlyout(
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.a_a_d_logo, size: 14),
              text: const Text('Cold boot'),
              onPressed: avd.isRunning ? null : () => run(widget.onColdBoot),
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.command_prompt, size: 14),
              text: const Text('Emulator console'),
              onPressed: () => run(widget.onConsole),
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.copy, size: 14),
              text: const Text('Duplicate'),
              onPressed: () => run(widget.onDuplicate),
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.clear_selection, size: 14),
              text: const Text('Wipe data'),
              onPressed: avd.isRunning ? null : () => run(widget.onWipe),
            ),
            MenuFlyoutItem(
              leading: Icon(
                FluentIcons.delete,
                size: 14,
                color: AppPalette.of(context).statusError,
              ),
              text: Text(
                'Delete',
                style: TextStyle(color: AppPalette.of(context).statusError),
              ),
              onPressed: avd.isRunning ? null : () => run(widget.onDelete),
            ),
          ],
        );
      },
    );
  }
}
