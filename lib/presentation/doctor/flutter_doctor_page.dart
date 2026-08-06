import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/doctor/doctor_fix_cubit.dart';
import '../../application/doctor/flutter_doctor_cubit.dart';
import '../../application/shell/shell_navigator.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/doctor_issue.dart';
import '../../domain/entities/doctor_report.dart';
import '../../infrastructure/system/external_link_service.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'doctor_animations.dart';
import 'widgets/doctor_fix_dialog.dart';
import 'widgets/doctor_indicators.dart';
import 'widgets/doctor_progress_bar.dart';

/// Flutter doctor: runs `flutter doctor -v` and shows each check resolving
/// live, then hands the same rows over to the interactive results view.
class FlutterDoctorPage extends StatelessWidget {
  const FlutterDoctorPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Normally does NOT auto-run — the user starts diagnostics explicitly. The
    // one exception is arriving from the Dashboard's "Run flutter doctor",
    // which is a request to run, not just to look.
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) {
            final cubit = getIt<FlutterDoctorCubit>();
            if (getIt<ShellNavigator>().consumeAutoRun(
              ShellDestination.flutterDoctor,
            )) {
              cubit.run();
            }
            return cubit;
          },
        ),
        BlocProvider(create: (_) => getIt<DoctorFixCubit>()),
      ],
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
                // A run while a fix is mid-flight would report the state the
                // fix is in the middle of changing.
                onPressed: context.watch<DoctorFixCubit>().state.isRunning
                    ? null
                    : cubit.run,
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
    // Checks stream in one at a time and carry their own per-row state, so the
    // skeleton only covers the gap before the first one lands.
    return LoadingSwitcher(
      showSkeleton: state.checks.isEmpty,
      skeleton: const DoctorSkeleton(),
      builder: (context) => _RunView(state: state),
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    await displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('Copied'),
          content: const Text('Doctor output copied to clipboard.'),
          severity: InfoBarSeverity.info,
          onClose: close,
        );
      },
    );
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

  /// Set by a fix whose change only new processes can see. Survives until the
  /// next run, which is the only thing that can prove it landed.
  String? _restartNote;

  @override
  void didUpdateWidget(covariant _RunView old) {
    super.didUpdateWidget(old);
    // A new run starts from collapsed rows.
    if (!old.state.isRunning && widget.state.isRunning) {
      _expanded.clear();
      _restartNote = null;
    }
  }

  /// The problems each finished check has, keyed by check name.
  Map<String, List<DoctorIssue>> get _issues => {
        for (final check in widget.state.checks)
          if (check.isDone)
            check.name: issuesFor(
              category: check.name,
              status: check.status,
              detailLines: check.details,
            ),
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = widget.state;
    final issues = _issues;
    final fixState = context.watch<DoctorFixCubit>().state;
    // One fix at a time, and never while doctor itself is running.
    final busy = fixState.isRunning || state.isRunning;

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
          if (_restartNote != null) ...[
            const SizedBox(height: 12),
            InfoBar(
              title: const Text('Restart required'),
              content: Text(_restartNote!),
              severity: InfoBarSeverity.warning,
              isLong: true,
              action: Button(
                onPressed: busy
                    ? null
                    : () {
                        setState(() => _restartNote = null);
                        context.read<FlutterDoctorCubit>().run();
                      },
                child: const Text('Re-run doctor anyway'),
              ),
              onClose: () => setState(() => _restartNote = null),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const SectionLabel('Checks'),
              const Spacer(),
              if (_autoFixable(issues).isNotEmpty)
                OutlinedActionButton(
                  icon: FluentIcons.repair,
                  label: 'Fix all',
                  dense: true,
                  busy: fixState.isRunning,
                  onPressed: busy ? null : () => _fixAll(issues),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GroupedList(
            children: [
              for (final check in state.checks)
                _CheckRow(
                  key: ValueKey(check.name),
                  check: check,
                  issues: issues[check.name] ?? const [],
                  busy: busy,
                  onFix: (issue) => _fix(issue),
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

  /// Every issue "Fix all" would act on, in check order.
  List<DoctorIssue> _autoFixable(Map<String, List<DoctorIssue>> issues) => [
        for (final list in issues.values)
          for (final issue in list)
            if (issue.kind == FixKind.auto) issue,
      ];

  /// Runs one issue's remedy: a dialog for anything with an executor, a jump
  /// somewhere else for a redirect.
  Future<void> _fix(DoctorIssue issue) async {
    final doctor = context.read<FlutterDoctorCubit>();
    final fixes = context.read<DoctorFixCubit>();

    if (issue.kind == FixKind.redirect || !fixes.canFix(issue)) {
      await _redirect(issue);
      return;
    }

    final result = await showDoctorFixDialog(
      context,
      issue: issue,
      cubit: fixes,
    );
    if (!mounted) return;
    if (result.rerun) {
      doctor.run();
    } else if (result.succeeded &&
        (result.restartRequired || result.blocksRerun)) {
      setState(() => _restartNote = result.note ??
          'Environment changes only reach processes started from now on.');
    }
  }

  /// Redirects go outside the app, or to the screen that owns the problem.
  Future<void> _redirect(DoctorIssue issue) async {
    if (issue.id == 'no_devices') {
      getIt<ShellNavigator>().go(ShellDestination.virtualDevices);
      return;
    }
    final url = issue.url ?? kWindowsInstallDocs;
    final opened = await getIt<ExternalLinkService>().open(url);
    if (!mounted || opened) return;
    await displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Could not open the link'),
        content: Text(url),
        severity: InfoBarSeverity.warning,
        onClose: close,
      ),
    );
  }

  /// Runs every automatic fix, then says what still needs a person.
  Future<void> _fixAll(Map<String, List<DoctorIssue>> issues) async {
    final doctor = context.read<FlutterDoctorCubit>();
    final fixes = context.read<DoctorFixCubit>();
    final all = [
      for (final list in issues.values) ...list,
    ];

    final report = await fixes.runAll(all);
    fixes.reset();
    if (!mounted) return;

    final parts = <String>[
      if (report.fixed.isNotEmpty)
        '${report.fixed.length} fixed'
      else
        'nothing could be fixed automatically',
      if (report.failedOn != null) '"${report.failedOn!.title}" failed',
      if (report.needsAttention.isNotEmpty)
        '${report.needsAttention.length} need your attention: '
            '${report.needsAttention.map((i) => i.title).join(', ')}',
    ];

    await displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(report.anythingChanged ? 'Fixes applied' : 'Nothing to do'),
        content: Text(parts.join(' · ')),
        severity: report.failedOn != null
            ? InfoBarSeverity.warning
            : InfoBarSeverity.info,
        isLong: true,
        onClose: close,
      ),
    );
    if (!mounted) return;

    if (report.restartRequired || report.blocksRerun) {
      setState(() => _restartNote =
          'Environment changes only reach processes started from now on.');
    } else if (report.anythingChanged) {
      doctor.run();
    }
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
        style: AppTextStyles.of(context).statusLine,
      );
    } else if (state.status == DoctorRunStatus.interrupted) {
      message = Text(
        '${state.errorMessage ?? 'Interrupted'} · ${state.doneCount} of '
        '$total checks completed',
        style: AppTextStyles.of(context).statusLine,
      );
    } else {
      message = Text(
        _summary(state),
        style: AppTextStyles.of(context).statusLine,
      );
    }

    return Row(
      children: [
        StatusDotFor(state: state),
        const SizedBox(width: 8),
        Expanded(child: message),
        const SizedBox(width: 12),
        Text(
          _format(state.elapsed),
          style: AppTextStyles.of(context).monoValue,
        ),
      ],
    );
  }

  static String _summary(FlutterDoctorState state) {
    final ok = state.count(DoctorStatus.ok);
    final warn = state.count(DoctorStatus.warning);
    final err = state.count(DoctorStatus.error);
    final total = state.checks.length;
    final problems = warn + err;
    if (problems > 0) {
      // The dot beside this already carries the severity, so the count is
      // what the sentence is for.
      return '$problems problem${problems == 1 ? '' : 's'} found — '
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
    this.issues = const [],
    this.busy = false,
    this.onFix,
    this.onTap,
  });

  final DoctorCheck check;
  final bool expanded;

  /// The problems this check has, one button each.
  final List<DoctorIssue> issues;

  /// True while another fix — or doctor itself — is running.
  final bool busy;

  final ValueChanged<DoctorIssue>? onFix;
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
          Flexible(child: _title(palette)),
        ],
      ),
      trailing: [
        // One button per problem: an Android toolchain missing both its
        // licences and cmdline-tools is two separate jobs.
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: OutlinedActionButton(
              icon: issue.kind == FixKind.redirect
                  ? FluentIcons.navigate_external_inline
                  : FluentIcons.repair,
              label: issue.actionLabel,
              dense: true,
              tooltip: issue.title,
              onPressed:
                  busy || onFix == null ? null : () => onFix!(issue),
            ),
          ),
        if (running)
          const RowSpinner()
        else if (check.elapsed != null)
          Text(
            _format(check.elapsed!),
            style: AppTextStyles.of(context).monoValue,
          ),
        if (check.isDone && check.canExpand)
          SizedBox(
            width: 13,
            child: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: DoctorAnimations.scale(
                context,
                DoctorAnimations.rowEnter,
              ),
              child: Icon(
                FluentIcons.chevron_down,
                size: 13,
                color: palette.textMuted,
              ),
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

  Widget _title(AppPalette palette) {
    final text = AppTextStyles.fromPalette(palette);
    if (check.phase == DoctorCheckPhase.running) {
      return Text.rich(
        TextSpan(
          text: check.name,
          style: text.rowTitle,
          children: [
            TextSpan(
              text: ' · checking',
              style: text.rowSecondary,
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        text: check.name,
        style: text.rowTitle,
        children: [
          if (check.summary != null)
            TextSpan(
              text: ' · ${check.summary}',
              style: text.rowSecondary,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _details(AppPalette palette) {
    final text = AppTextStyles.fromPalette(palette);
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
            SelectableText(line, style: text.monoBody),
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
