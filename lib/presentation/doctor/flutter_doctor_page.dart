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
import '../common/status_dot.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Flutter Doctor: runs `flutter doctor -v` on demand and lists the results.
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
        final hasReport = state.report != null;
        return PageScaffold(
          title: 'Flutter doctor',
          actions: [
            if (hasReport)
              OutlinedActionButton(
                icon: FluentIcons.copy,
                label: 'Copy output',
                onPressed: () => _copy(context, state.report!.rawOutput),
              ),
            OutlinedActionButton(
              icon: hasReport ? FluentIcons.refresh : FluentIcons.play,
              label: hasReport ? 'Run again' : 'Run doctor',
              busy: state.isRunning,
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
    switch (state.status) {
      case DoctorRunStatus.initial:
        return EmptyState(
          icon: FluentIcons.health,
          title: 'Check your Flutter environment',
          message: 'Runs "flutter doctor -v" and lists what needs fixing.',
          actionLabel: 'Run doctor',
          actionIcon: FluentIcons.play,
          onAction: cubit.run,
        );
      case DoctorRunStatus.running when state.report == null:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProgressRing(),
              SizedBox(height: 14),
              Text('Running flutter doctor…', style: AppTextStyles.statusLine),
              SizedBox(height: 4),
              Text('This can take a moment on the first run.',
                  style: AppTextStyles.caption),
            ],
          ),
        );
      case DoctorRunStatus.failure:
        return EmptyState(
          icon: FluentIcons.error_badge,
          isError: true,
          title: 'Could not run flutter doctor',
          message: state.errorMessage ?? 'Unknown error.',
          actionLabel: 'Retry',
          onAction: cubit.run,
        );
      default:
        final report = state.report;
        if (report == null) {
          return EmptyState(
            icon: FluentIcons.health,
            title: 'Check your Flutter environment',
            message: 'Runs "flutter doctor -v" and lists what needs fixing.',
            actionLabel: 'Run doctor',
            actionIcon: FluentIcons.play,
            onAction: cubit.run,
          );
        }
        return _Results(report: report, running: state.isRunning);
    }
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

class _Results extends StatefulWidget {
  const _Results({required this.report, required this.running});

  final DoctorReport report;
  final bool running;

  @override
  State<_Results> createState() => _ResultsState();
}

class _ResultsState extends State<_Results> {
  final Set<int> _expanded = {};

  @override
  void didUpdateWidget(covariant _Results old) {
    super.didUpdateWidget(old);
    if (old.report != widget.report) _expanded.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final report = widget.report;
    final ok = report.count(DoctorStatus.ok);
    final warn = report.count(DoctorStatus.warning);
    final err = report.count(DoctorStatus.error);

    final Color color;
    final String message;
    if (err > 0) {
      color = palette.statusError;
      message = 'Action required — $err error${err == 1 ? '' : 's'}, '
          '$warn warning${warn == 1 ? '' : 's'}, $ok passed';
    } else if (warn > 0) {
      color = palette.statusWarn;
      message = 'A few things to check — '
          '$warn warning${warn == 1 ? '' : 's'}, $ok passed';
    } else {
      color = palette.statusOk;
      message = 'All checks passed — $ok of ${report.sections.length}';
    }

    return SingleChildScrollView(
      padding: kPageBodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusLine(
            color: widget.running ? palette.textMuted : color,
            message: widget.running ? 'Re-running flutter doctor…' : message,
          ),
          const SizedBox(height: 18),
          const SectionLabel('Checks'),
          const SizedBox(height: 8),
          GroupedList(
            children: [
              for (var i = 0; i < report.sections.length; i++)
                _CheckRow(
                  section: report.sections[i],
                  expanded: _expanded.contains(i),
                  onTap: () => setState(() {
                    _expanded.contains(i)
                        ? _expanded.remove(i)
                        : _expanded.add(i);
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One check: status dot, name, one-line summary, expandable raw output.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.section,
    required this.expanded,
    required this.onTap,
  });

  final DoctorSection section;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasDetails = section.details.isNotEmpty;

    return GroupedListRow(
      statusColor: _statusColor(section.status, palette),
      showStatusSlot: true,
      title: _shortTitle(section.title),
      secondary: _parenthetical(section.title),
      onTap: hasDetails ? onTap : null,
      trailing: [
        SizedBox(
          width: 13,
          child: hasDetails
              ? AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(FluentIcons.chevron_down,
                      size: 13, color: palette.textMuted),
                )
              : null,
        ),
      ],
      below: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: hasDetails && expanded
            ? Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10, left: 16),
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  border:
                      Border(left: BorderSide(color: palette.border, width: 2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in section.details)
                      SelectableText(line, style: AppTextStyles.monoBody),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }

  /// Title text before the first parenthesis, e.g. "Flutter".
  static String _shortTitle(String title) {
    final i = title.indexOf('(');
    return (i > 0 ? title.substring(0, i) : title).trim();
  }

  /// The parenthetical descriptor, e.g. "Channel stable, 3.44.1, on …".
  static String? _parenthetical(String title) {
    final match = RegExp(r'\(([^)]*)\)').firstMatch(title);
    return match?.group(1)?.trim();
  }

  static Color _statusColor(DoctorStatus status, AppPalette palette) =>
      switch (status) {
        DoctorStatus.ok => palette.statusOk,
        DoctorStatus.warning => palette.statusWarn,
        DoctorStatus.error => palette.statusError,
        DoctorStatus.info => palette.textMuted,
      };
}
