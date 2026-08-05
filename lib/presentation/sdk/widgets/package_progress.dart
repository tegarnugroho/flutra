import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/sdk/sdk_manager_cubit.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// A bottom bar showing the active install and its progress, with cancel.
/// Shared by the SDK Manager and Updates pages.
class PackageQueueBar extends StatelessWidget {
  const PackageQueueBar({super.key, required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: palette.sidebarBg,
        border: Border(
          top: BorderSide(color: palette.border, width: AppShape.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.activePath ?? 'Working…',
                  style: AppTextStyles.of(context).monoValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                ProgressBar(
                  value: state.progress != null ? state.progress! * 100 : null,
                  activeColor: palette.accent,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (state.queue.isNotEmpty)
            Text('${state.queue.length} queued',
                style: AppTextStyles.of(context).caption),
          const SizedBox(width: 12),
          OutlinedActionButton(
            icon: FluentIcons.cancel,
            label: 'Cancel',
            dense: true,
            onPressed: cubit.cancel,
          ),
        ],
      ),
    );
  }
}

/// A collapsible terminal panel streaming the executed sdkmanager output.
class PackageConsole extends StatefulWidget {
  const PackageConsole({super.key, required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  State<PackageConsole> createState() => _PackageConsoleState();
}

class _PackageConsoleState extends State<PackageConsole> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    final palette = AppPalette.of(context);
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.logBg,
        border: Border(
          top: BorderSide(color: palette.border, width: AppShape.hairline),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: palette.border, width: AppShape.hairline),
              ),
            ),
            child: Row(
              children: [
                Icon(FluentIcons.command_prompt,
                    size: 12, color: palette.textMuted),
                const SizedBox(width: 8),
                const Text('Console', style: AppTextStyles.of(context).sectionLabel),
                const Spacer(),
                OutlinedActionButton(
                  icon: FluentIcons.clear,
                  dense: true,
                  tooltip: 'Clear',
                  onPressed: widget.cubit.clearConsole,
                ),
                const SizedBox(width: 8),
                OutlinedActionButton(
                  icon: FluentIcons.chevron_down,
                  dense: true,
                  tooltip: 'Hide',
                  onPressed: widget.cubit.toggleConsole,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(10),
              itemCount: widget.state.console.length,
              itemBuilder: (context, i) {
                final line = widget.state.console[i];
                // The cubit marks executed commands with "$" and failures
                // with "✗"; everything else is plain tool output.
                final isCommand = line.startsWith(r'$');
                final isError = line.startsWith('✗');
                return SelectableText(
                  line,
                  style: AppTextStyles.of(context).monoLog.copyWith(
                    color: isError
                        ? palette.statusError
                        : isCommand
                            ? palette.textTertiary
                            : palette.textSecondary,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
