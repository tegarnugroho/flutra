import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/flutter_sdk/version_switch_cubit.dart';
import '../../domain/entities/version_switch.dart';
import '../common/app_loader.dart';
import '../common/command_log_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Runs a version switch in a modal, showing one line per stage plus the raw
/// git/flutter output, and resolves to the outcome — or null when it failed or
/// was closed before finishing.
///
/// The dialog has no Cancel: stopping between the checkout and the tool-cache
/// rebuild is exactly the half-switched state the switch exists to avoid.
Future<VersionSwitchOutcome?> showVersionSwitchDialog(
  BuildContext context, {
  required String version,
  required String channel,
  required Stream<VersionSwitchEvent> Function() start,
}) async {
  return showDialog<VersionSwitchOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BlocProvider(
      create: (_) => VersionSwitchCubit(version, start),
      child: _VersionSwitchDialog(version: version, channel: channel),
    ),
  );
}

class _VersionSwitchDialog extends StatefulWidget {
  const _VersionSwitchDialog({required this.version, required this.channel});

  final String version;
  final String channel;

  @override
  State<_VersionSwitchDialog> createState() => _VersionSwitchDialogState();
}

class _VersionSwitchDialogState extends State<_VersionSwitchDialog> {
  @override
  void initState() {
    super.initState();
    context.read<VersionSwitchCubit>().run();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return BlocBuilder<VersionSwitchCubit, VersionSwitchProgress>(
      builder: (context, state) {
        final failure = state.failure;
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 640),
          title: Row(
            children: [
              Expanded(
                child: Text('Switching to Flutter ${widget.version}'),
              ),
              if (state.running)
                AppLoader(size: AppLoaderSize.small)
              else if (state.isSuccess)
                Icon(FluentIcons.completed_solid, color: palette.statusOk)
              else
                Icon(FluentIcons.error_badge, color: palette.statusError),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Checking the tag out onto the "${widget.channel}" branch so '
                'Flutter keeps reporting an official channel.',
                style: AppTextStyles.of(context).caption,
              ),
              const SizedBox(height: 12),
              _StepList(state: state),
              const SizedBox(height: 12),
              LogLinesView(
                lines: state.lines,
                height: 220,
                starting: state.running,
              ),
              if (failure != null) ...[
                const SizedBox(height: 12),
                InfoBar(
                  title: const Text('Switch failed'),
                  content: Text(
                    failure.rolledBack
                        ? 'The SDK was put back where it was.'
                        : failure.suggestion ??
                            'The SDK was not moved off its previous version.',
                  ),
                  severity: InfoBarSeverity.error,
                  isLong: true,
                ),
              ],
            ],
          ),
          actions: [
            if (!state.running)
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(state.outcome),
                child: const Text('Close'),
              ),
          ],
        );
      },
    );
  }
}

/// The five stages, ticked off as they complete.
class _StepList extends StatelessWidget {
  const _StepList({required this.state});

  final VersionSwitchProgress state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final styles = AppTextStyles.of(context);
    final failedAt = state.failure == null ? null : state.step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in VersionSwitchStep.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: _marker(context, step, failedAt),
                ),
                const SizedBox(width: 8),
                Text(
                  step.label(state.version),
                  style: state.completed.contains(step) || state.step == step
                      ? styles.rowTitle
                      : styles.caption.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _marker(
      BuildContext context, VersionSwitchStep step, VersionSwitchStep? failedAt) {
    final palette = AppPalette.of(context);
    if (step == failedAt) {
      return Icon(FluentIcons.error_badge, size: 13, color: palette.statusError);
    }
    if (state.completed.contains(step)) {
      return Icon(FluentIcons.completed_solid,
          size: 13, color: palette.statusOk);
    }
    if (state.step == step && state.running) {
      return AppLoader(size: AppLoaderSize.small);
    }
    return Icon(FluentIcons.circle_ring, size: 11, color: palette.textMuted);
  }
}
