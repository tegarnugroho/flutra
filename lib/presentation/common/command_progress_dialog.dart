import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/common/command_log_cubit.dart';
import '../../core/command/command_runner.dart';
import '../theme/app_colors.dart';
import 'app_loader.dart';
import 'command_log_view.dart';

/// Runs [start], streams its output in a modal dialog, and resolves to whether
/// the command succeeded (exit code 0). The dialog cannot be dismissed until the
/// command finishes or is cancelled.
Future<bool> showCommandProgressDialog(
  BuildContext context, {
  required String title,
  required Future<RunningCommand> Function() start,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BlocProvider(
      create: (_) => CommandLogCubit(),
      child: _CommandProgressDialog(title: title, start: start),
    ),
  );
  return result ?? false;
}

class _CommandProgressDialog extends StatefulWidget {
  const _CommandProgressDialog({required this.title, required this.start});

  final String title;
  final Future<RunningCommand> Function() start;

  @override
  State<_CommandProgressDialog> createState() => _CommandProgressDialogState();
}

class _CommandProgressDialogState extends State<_CommandProgressDialog> {
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final cubit = context.read<CommandLogCubit>();
    try {
      final command = await widget.start();
      await cubit.attach(command);
    } catch (e) {
      // start() itself failed (e.g. executable missing) — surface and close.
      if (mounted) {
        Navigator.of(context).pop(false);
        await displayInfoBar(
          context,
          builder: (context, close) {
            return InfoBar(
              title: const Text('Failed to start'),
              content: Text('$e'),
              severity: InfoBarSeverity.error,
              onClose: close,
            );
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CommandLogCubit, CommandLogState>(
      builder: (context, state) {
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 640),
          title: Row(
            children: [
              Expanded(child: Text(widget.title)),
              if (state.running)
                AppLoader(size: AppLoaderSize.small)
              else if (state.isSuccess)
                Icon(
                  FluentIcons.completed_solid,
                  color: AppPalette.of(context).statusOk,
                )
              else
                Icon(
                  FluentIcons.error_badge,
                  color: AppPalette.of(context).statusError,
                ),
            ],
          ),
          content: const CommandLogView(),
          actions: [
            if (state.running)
              Button(
                onPressed: () => context.read<CommandLogCubit>().cancel(),
                child: const Text('Cancel'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(context).pop(state.isSuccess),
                child: const Text('Close'),
              ),
          ],
        );
      },
    );
  }
}
