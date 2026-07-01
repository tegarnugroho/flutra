import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/tool_status.dart';

/// A card summarising the status of a single tool on the dashboard.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.status});

  final ToolStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final visuals = _StateVisuals.of(status.state);

    return Card(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: visuals.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_kindIcon(status.kind), size: 22, color: visuals.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status.displayName,
                        style: theme.typography.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(visuals.icon, size: 16, color: visuals.color),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle(status, visuals.label),
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (status.path != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    status.path!,
                    style: theme.typography.caption?.copyWith(
                      fontSize: 11,
                      color: theme.resources.textFillColorTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(ToolStatus status, String stateLabel) {
    final buffer = StringBuffer(stateLabel);
    if (status.version != null) buffer.write(' • v${status.version}');
    if (status.detail != null) buffer.write('\n${status.detail}');
    return buffer.toString();
  }

  static IconData _kindIcon(ToolKind kind) => switch (kind) {
        ToolKind.sdk => FluentIcons.build_queue,
        ToolKind.java => FluentIcons.coffee_script,
        ToolKind.flutter => FluentIcons.developer_tools,
        ToolKind.emulator => FluentIcons.cell_phone,
        ToolKind.adb => FluentIcons.plug_connected,
      };
}

/// Maps a [ToolState] to its colour, icon and label.
class _StateVisuals {
  const _StateVisuals(this.color, this.icon, this.label);

  final Color color;
  final IconData icon;
  final String label;

  factory _StateVisuals.of(ToolState state) => switch (state) {
        ToolState.installed => const _StateVisuals(
            Color(0xFF3DDC84), FluentIcons.completed_solid, 'Installed'),
        ToolState.needsUpdate => const _StateVisuals(
            Color(0xFFFFB900), FluentIcons.warning, 'Update available'),
        ToolState.missing => const _StateVisuals(
            Color(0xFFE81123), FluentIcons.status_error_full, 'Missing'),
        ToolState.checking => const _StateVisuals(
            Color(0xFF767676), FluentIcons.sync, 'Checking…'),
        ToolState.error => const _StateVisuals(
            Color(0xFFE81123), FluentIcons.error_badge, 'Error'),
      };
}
