import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/tool_status.dart';
import '../../theme/app_colors.dart';

/// A small filled circle — the only place colour appears in the dashboard.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Maps a detected [ToolState] onto a semantic status token.
Color statusColorOf(ToolState state, AppPalette palette) => switch (state) {
      ToolState.installed => palette.statusOk,
      ToolState.needsUpdate => palette.statusWarn,
      ToolState.missing => palette.statusError,
      ToolState.error => palette.statusError,
      ToolState.checking => palette.textMuted,
    };
