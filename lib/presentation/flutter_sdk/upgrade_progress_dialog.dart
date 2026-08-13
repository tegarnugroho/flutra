import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/flutter_sdk/flutter_upgrade_cubit.dart';
import '../../core/command/command_runner.dart';
import 'widgets/upgrade_progress_view.dart';

/// Runs `flutter upgrade` in a phased-progress modal and resolves to whether it
/// succeeded. The dialog cannot be dismissed until the upgrade finishes or is
/// cancelled.
///
/// [currentVersion] and [targetVersion] come from the SDK screen's state — the
/// target is null when the release index could not say what the channel tip is.
Future<bool> showUpgradeProgressDialog(
  BuildContext context, {
  required String currentVersion,
  required String channel,
  String? targetVersion,
  required Future<RunningCommand> Function() start,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BlocProvider(
      create: (_) => FlutterUpgradeCubit(),
      child: _UpgradeProgressDialog(
        currentVersion: currentVersion,
        targetVersion: targetVersion,
        channel: channel,
        start: start,
      ),
    ),
  );
  return result ?? false;
}

class _UpgradeProgressDialog extends StatefulWidget {
  const _UpgradeProgressDialog({
    required this.currentVersion,
    required this.targetVersion,
    required this.channel,
    required this.start,
  });

  final String currentVersion;
  final String? targetVersion;
  final String channel;
  final Future<RunningCommand> Function() start;

  @override
  State<_UpgradeProgressDialog> createState() => _UpgradeProgressDialogState();
}

class _UpgradeProgressDialogState extends State<_UpgradeProgressDialog> {
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final cubit = context.read<FlutterUpgradeCubit>();
    try {
      final command = await widget.start();
      await cubit.attach(command);
    } catch (e) {
      // start() itself failed (e.g. the executable went missing) — surface and
      // close, exactly as the generic command dialog does.
      if (mounted) {
        Navigator.of(context).pop(false);
        await displayInfoBar(
          context,
          builder: (context, close) {
            return InfoBar(
              title: const Text(UpgradeStrings.startFailed),
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
    return BlocConsumer<FlutterUpgradeCubit, UpgradeProgress>(
      // A failure is the one time the log is worth reading, so open it.
      listenWhen: (previous, current) =>
          !previous.isFailure && current.isFailure,
      listener: (context, state) => setState(() => _showDetails = true),
      builder: (context, state) {
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 440),
          title: UpgradeDialogHeader(
            progress: state,
            channel: widget.channel,
            currentVersion: widget.currentVersion,
            targetVersion: widget.targetVersion,
          ),
          content: UpgradeDialogBody(
            progress: state,
            targetVersion: widget.targetVersion,
            showDetails: _showDetails,
            onToggleDetails: () =>
                setState(() => _showDetails = !_showDetails),
          ),
          actions: [
            if (!state.finished)
              Button(
                onPressed: context.read<FlutterUpgradeCubit>().cancel,
                child: const Text(UpgradeStrings.cancel),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(context).pop(state.isSuccess),
                child: Text(
                  state.isSuccess
                      ? UpgradeStrings.done
                      : UpgradeStrings.close,
                ),
              ),
          ],
        );
      },
    );
  }
}
