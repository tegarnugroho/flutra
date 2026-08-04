import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/environment_snapshot.dart';
import '../../../domain/entities/tool_status.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'grouped_list.dart';
import 'status_dot.dart';

/// The toolchain as a single dense row list: icon, name, inline detail,
/// right-aligned version and a status dot.
class ToolchainList extends StatelessWidget {
  const ToolchainList({super.key, required this.snapshot});

  final EnvironmentSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return GroupedList(
      children: [
        for (final status in snapshot.all)
          ToolchainRow(
            status: status,
            // The build-tools version belongs to the SDK row; it is no longer
            // repeated in the Paths list.
            version: status.kind == ToolKind.sdk
                ? snapshot.buildToolsVersion
                : status.version,
          ),
      ],
    );
  }
}

/// One tool. Hovering raises the row; there is no row action to invoke.
class ToolchainRow extends StatefulWidget {
  const ToolchainRow({super.key, required this.status, this.version});

  final ToolStatus status;
  final String? version;

  @override
  State<ToolchainRow> createState() => _ToolchainRowState();
}

class _ToolchainRowState extends State<ToolchainRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final status = widget.status;
    final detail = _inlineDetail(status);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        color: _hovered ? palette.surfaceRaised : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(_kindIcon(status.kind), size: 16, color: palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: status.displayName,
                  style: AppTextStyles.rowTitle,
                  children: [
                    if (detail != null)
                      TextSpan(
                        text: ' · $detail',
                        style: AppTextStyles.rowSecondary,
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.version != null && widget.version!.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(widget.version!, style: AppTextStyles.monoValue),
            ],
            const SizedBox(width: 10),
            StatusDot(color: statusColorOf(status.state, palette)),
          ],
        ),
      ),
    );
  }

  /// The detection layer joins its detail fragments with a bullet; the neutral
  /// theme uses a comma so the row reads as one sentence.
  static String? _inlineDetail(ToolStatus status) {
    final detail = status.detail;
    if (detail == null || detail.isEmpty) return null;
    return detail.replaceAll(' • ', ', ');
  }

  static IconData _kindIcon(ToolKind kind) => switch (kind) {
        ToolKind.sdk => FluentIcons.build_queue,
        ToolKind.java => FluentIcons.coffee_script,
        ToolKind.flutter => FluentIcons.developer_tools,
        ToolKind.emulator => FluentIcons.cell_phone,
        ToolKind.adb => FluentIcons.plug_connected,
      };
}
