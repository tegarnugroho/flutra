import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/sdk/sdk_manager_cubit.dart';
import '../../theme/app_colors.dart';

/// A bottom bar showing the active install and its progress, with cancel.
/// Shared by the SDK Manager and Package Downloader.
class PackageQueueBar extends StatelessWidget {
  const PackageQueueBar({super.key, required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        border: Border(
            top: BorderSide(color: theme.resources.controlStrokeColorDefault)),
      ),
      child: Row(
        children: [
          const SizedBox(
              width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.activePath ?? 'Working…',
                  style: theme.typography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ProgressBar(
                    value:
                        state.progress != null ? state.progress! * 100 : null),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (state.queue.isNotEmpty)
            Text('${state.queue.length} queued',
                style: theme.typography.caption),
          const SizedBox(width: 12),
          Button(onPressed: cubit.cancel, child: const Text('Cancel')),
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
    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0C),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF161616),
            child: Row(
              children: [
                const Icon(FluentIcons.command_prompt,
                    size: 12, color: Color(0xFFBBBBBB)),
                const SizedBox(width: 8),
                const Text('Console',
                    style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 12)),
                const Spacer(),
                Tooltip(
                  message: 'Clear',
                  child: IconButton(
                    icon: const Icon(FluentIcons.clear, size: 12),
                    onPressed: widget.cubit.clearConsole,
                  ),
                ),
                Tooltip(
                  message: 'Hide',
                  child: IconButton(
                    icon: const Icon(FluentIcons.chevron_down, size: 12),
                    onPressed: widget.cubit.toggleConsole,
                  ),
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
                final isCmd = line.startsWith('\$');
                final isErr = line.startsWith('✗');
                return SelectableText(
                  line,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    height: 1.35,
                    color: isCmd
                        ? AppColors.statusOk
                        : isErr
                            ? const Color(0xFFFF6B6B)
                            : const Color(0xFFD4D4D4),
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
