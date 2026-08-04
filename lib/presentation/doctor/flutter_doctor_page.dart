import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/doctor/flutter_doctor_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/doctor_report.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'doctor_animations.dart';
import 'widgets/doctor_indicators.dart';
import 'widgets/doctor_progress_bar.dart';

/// Flutter doctor: runs `flutter doctor -v` and shows each check resolving
/// live, then hands the same rows over to the interactive results view.
class FlutterDoctorPage extends StatelessWidget {
  const FlutterDoctorPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Does NOT auto-run — the user starts diagnostics explicitly.
    return BlocProvider(
      create: (_) => getIt<FlutterDoctorCubit>(),
      child: const _FlutterDoctorView(),
    );
  }
}

class _FlutterDoctorView extends StatelessWidget {
  const _FlutterDoctorView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FlutterDoctorCubit, FlutterDoctorState>(
      builder: (context, state) {
        final cubit = context.read<FlutterDoctorCubit>();
        final report = state.report;
        return PageScaffold(
          title: 'Flutter doctor',
          actions: [
            if (report != null && report.sections.isNotEmpty)
              OutlinedActionButton(
                icon: FluentIcons.copy,
                label: 'Copy output',
                onPressed: () => _copy(context, report.rawOutput),
              ),
            if (state.isRunning)
              OutlinedActionButton(
                icon: FluentIcons.refresh,
                label: 'Running',
                busy: true,
                // Discoverable cancel: the label changes under the pointer.
                hoverLabel: 'Cancel',
                hoverIcon: FluentIcons.cancel,
                onPressed: cubit.cancel,
              )
            else
              OutlinedActionButton(
                icon: state.hasChecks ? FluentIcons.refresh : FluentIcons.play,
                label: state.hasChecks ? 'Run again' : 'Run doctor',
                onPressed: cubit.run,
              ),
          ],
          child: _body(context, state, cubit),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    FlutterDoctorState state,
    FlutterDoctorCubit cubit,
  ) {
    if (state.status == DoctorRunStatus.initial) {
      return EmptyState(
        icon: FluentIcons.health,
        title: 'Check your Flutter environment',
        message: 'Runs "flutter doctor -v" and lists what needs fixing.',
        actionLabel: 'Run doctor',
        actionIcon: FluentIcons.play,
        onAction: cubit.run,
      );
    }
    if (state.status == DoctorRunStatus.failure) {
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Could not run flutter doctor',
        message: state.errorMessage ?? 'Unknown error.',
        actionLabel: 'Retry',
        onAction: cubit.run,
      );
    }
    return _RunView(state: state);
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    await displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('Copied'),
        content: const Text('Doctor output copied to clipboard.'),
        severity: InfoBarSeverity.info,
        onClose: close,
      );
    });
  }
}

/// The running and finished states share this view — the rows never swap, they
/// just stop being pending and start being expandable.
class _RunView extends StatefulWidget {
  const _RunView({required this.state});

  final FlutterDoctorState state;

  @override
  State<_RunView> createState() => _RunViewState();
}

class _RunViewState extends State<_RunView> {
  /// Expanded rows, by check name — purely view state.
  final Set<String> _expanded = {};

  @override
  void didUpdateWidget(covariant _RunView old) {
    super.didUpdateWidget(old);
    // A new run starts from collapsed rows.
    if (!old.state.isRunning && widget.state.isRunning) _expanded.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = widget.state;

    return SingleChildScrollView(
      padding: kPageBodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusLine(state: state),
          const SizedBox(height: 8),
          DoctorProgressBar(
            progress: state.progress,
            completed: !state.isRunning,
            completionColor: _summaryColor(state, palette),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Checks'),
          const SizedBox(height: 8),
          GroupedList(
            children: [
              for (final check in state.checks)
                _CheckRow(
                  key: ValueKey(check.name),
                  check: check,
                  expanded: _expanded.contains(check.name),
                  onTap: check.isDone && check.canExpand
                      ? () => setState(() {
                            _expanded.contains(check.name)
                                ? _expanded.remove(check.name)
                                : _expanded.add(check.name);
                          })
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Progress sentence plus the ticking total, or the final summary.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final FlutterDoctorState state;

  @override
  Widget build(BuildContext context) {
    final total = state.checks.length;

    Widget message;
    if (state.isRunning) {
      message = AnimatedEllipsisText(
        'Running checks · ${state.doneCount} of $total',
        style: AppTextStyles.statusLine,
      );
    } else if (state.status == DoctorRunStatus.interrupted) {
      message = Text(
        '${state.errorMessage ?? 'Interrupted'} · ${state.doneCount} of '
        '$total checks completed',
        style: AppTextStyles.statusLine,
      );
    } else {
      message = Text(_summary(state), style: AppTextStyles.statusLine);
    }

    return Row(
      children: [
        StatusDotFor(state: state),
        const SizedBox(width: 8),
        Expanded(child: message),
        const SizedBox(width: 12),
        Text(_format(state.elapsed), style: AppTextStyles.monoValue),
      ],
    );
  }

  static String _summary(FlutterDoctorState state) {
    final ok = state.count(DoctorStatus.ok);
    final warn = state.count(DoctorStatus.warning);
    final err = state.count(DoctorStatus.error);
    final total = state.checks.length;
    if (err > 0) {
      return 'Action required — $err error${err == 1 ? '' : 's'}, '
          '$warn warning${warn == 1 ? '' : 's'}, $ok of $total passed';
    }
    if (warn > 0) {
      return 'A few things to check — $warn warning${warn == 1 ? '' : 's'}, '
          '$ok of $total passed';
    }
    return 'All checks passed — $ok of $total';
  }

  static String _format(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

/// The dot on the status line: accent while running, semantic when finished.
class StatusDotFor extends StatelessWidget {
  const StatusDotFor({super.key, required this.state});

  final FlutterDoctorState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (state.isRunning) return const PulsingDot(size: 7);
    return PoppingStatusDot(color: _summaryColor(state, palette), size: 7);
  }
}

Color _summaryColor(FlutterDoctorState state, AppPalette palette) {
  if (state.count(DoctorStatus.error) > 0 ||
      state.status == DoctorRunStatus.interrupted) {
    return palette.statusError;
  }
  if (state.count(DoctorStatus.warning) > 0) return palette.statusWarn;
  return palette.statusOk;
}

/// One check row, in whichever phase it is currently in.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.check,
    required this.expanded,
    this.onTap,
  });

  final DoctorCheck check;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pending = check.phase == DoctorCheckPhase.pending;
    final running = check.phase == DoctorCheckPhase.running;

    final row = GroupedListRow(
      onTap: onTap,
      background: running ? palette.accentBgTint : null,
      titleWidget: Row(
        children: [
          _dot(),
          const SizedBox(width: 10),
          Flexible(child: _title()),
        ],
      ),
      trailing: [
        if (running)
          const RowSpinner()
        else if (check.elapsed != null)
          Text(_format(check.elapsed!), style: AppTextStyles.monoValue),
        if (check.isDone && check.canExpand)
          SizedBox(
            width: 13,
            child: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration:
                  DoctorAnimations.scale(context, DoctorAnimations.rowEnter),
              child: Icon(FluentIcons.chevron_down,
                  size: 13, color: palette.textMuted),
            ),
          ),
      ],
      below: AnimatedSize(
        duration: DoctorAnimations.scale(context, DoctorAnimations.rowEnter),
        curve: DoctorAnimations.rowEnterCurve,
        alignment: Alignment.topCenter,
        child: expanded && check.canExpand
            ? _details(palette)
            : const SizedBox(width: double.infinity),
      ),
    );

    // Pending rows sit dimmed and 4px low; resolving lifts and reveals them.
    return AnimatedSlide(
      offset: pending ? const Offset(0, 0.06) : Offset.zero,
      duration: DoctorAnimations.scale(context, DoctorAnimations.rowEnter),
      curve: DoctorAnimations.rowEnterCurve,
      child: AnimatedOpacity(
        opacity: pending ? 0.38 : 1,
        duration: DoctorAnimations.scale(context, DoctorAnimations.rowEnter),
        curve: DoctorAnimations.rowEnterCurve,
        child: row,
      ),
    );
  }

  Widget _dot() {
    switch (check.phase) {
      case DoctorCheckPhase.pending:
        return const PendingDot();
      case DoctorCheckPhase.running:
        return const PulsingDot();
      case DoctorCheckPhase.done:
        return _StatusDotBuilder(status: check.status);
    }
  }

  Widget _title() {
    if (check.phase == DoctorCheckPhase.running) {
      return Text.rich(
        TextSpan(
          text: check.name,
          style: AppTextStyles.rowTitle,
          children: const [
            TextSpan(text: ' · checking', style: AppTextStyles.rowSecondary),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        text: check.name,
        style: AppTextStyles.rowTitle,
        children: [
          if (check.summary != null)
            TextSpan(
              text: ' · ${check.summary}',
              style: AppTextStyles.rowSecondary,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _details(AppPalette palette) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, left: 16),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.border, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in check.details)
            SelectableText(line, style: AppTextStyles.monoBody),
        ],
      ),
    );
  }

  static String _format(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

class _StatusDotBuilder extends StatelessWidget {
  const _StatusDotBuilder({required this.status});

  final DoctorStatus? status;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = switch (status) {
      DoctorStatus.ok => palette.statusOk,
      DoctorStatus.warning => palette.statusWarn,
      DoctorStatus.error => palette.statusError,
      _ => palette.textMuted,
    };
    return PoppingStatusDot(color: color);
  }
}
