import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/doctor/flutter_doctor_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/doctor_report.dart';

/// Flutter Doctor: runs `flutter doctor -v` on demand and shows a health-score
/// dashboard of the results.
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
    final cubit = context.read<FlutterDoctorCubit>();
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Flutter Doctor'),
        commandBar: BlocBuilder<FlutterDoctorCubit, FlutterDoctorState>(
          builder: (context, state) {
            final hasReport = state.report != null;
            return CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.copy),
                  label: const Text('Copy'),
                  onPressed: hasReport
                      ? () => _copy(context, state.report!.rawOutput)
                      : null,
                ),
                CommandBarButton(
                  icon: state.isRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2))
                      : Icon(hasReport ? FluentIcons.refresh : FluentIcons.play),
                  label: Text(hasReport ? 'Run again' : 'Run'),
                  onPressed: state.isRunning ? null : cubit.run,
                ),
              ],
            );
          },
        ),
      ),
      content: BlocBuilder<FlutterDoctorCubit, FlutterDoctorState>(
        builder: (context, state) {
          switch (state.status) {
            case DoctorRunStatus.initial:
              return _StartView(onRun: cubit.run);
            case DoctorRunStatus.running when state.report == null:
              return const _RunningView();
            case DoctorRunStatus.failure:
              return _ErrorView(
                message: state.errorMessage ?? 'Unknown error.',
                onRetry: cubit.run,
              );
            default:
              final report = state.report;
              if (report == null) return _StartView(onRun: cubit.run);
              return _HealthDashboard(report: report, running: state.isRunning);
          }
        },
      ),
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    await displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('Copied'),
        content: const Text('Doctor output copied to clipboard.'),
        severity: InfoBarSeverity.success,
        onClose: close,
      );
    });
  }
}

// ---- Health dashboard -------------------------------------------------------

class _HealthDashboard extends StatefulWidget {
  const _HealthDashboard({required this.report, required this.running});

  final DoctorReport report;
  final bool running;

  @override
  State<_HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<_HealthDashboard> {
  final Set<int> _expanded = {};

  @override
  void didUpdateWidget(covariant _HealthDashboard old) {
    super.didUpdateWidget(old);
    if (old.report != widget.report) _expanded.clear();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _HealthHeader(report: report)),
        if (widget.running)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 4),
              child: ProgressBar(),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 28),
          sliver: SliverList.separated(
            itemCount: report.sections.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: 1),
            itemBuilder: (context, i) => _CheckRow(
              section: report.sections[i],
              expanded: _expanded.contains(i),
              onTap: () => setState(() {
                _expanded.contains(i)
                    ? _expanded.remove(i)
                    : _expanded.add(i);
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _HealthHeader extends StatelessWidget {
  const _HealthHeader({required this.report});

  final DoctorReport report;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final total = report.sections.isEmpty ? 1 : report.sections.length;
    final ok = report.count(DoctorStatus.ok);
    final warn = report.count(DoctorStatus.warning);
    final err = report.count(DoctorStatus.error);
    final ratio = ok / total;
    final color = err > 0
        ? const Color(0xFFE81123)
        : warn > 0
            ? const Color(0xFFFFB900)
            : const Color(0xFF3DDC84);
    final headline = err > 0
        ? 'Action required'
        : warn > 0
            ? 'A few things to check'
            : 'All systems go';

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 12),
      child: Row(
        children: [
          _HealthRing(ratio: ratio, color: color),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(headline, style: theme.typography.title),
                const SizedBox(height: 6),
                Text(
                  '$total checks completed',
                  style: theme.typography.body?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    _LegendDot(
                        color: const Color(0xFF3DDC84),
                        label: 'Passed',
                        count: ok),
                    _LegendDot(
                        color: const Color(0xFFFFB900),
                        label: 'Warnings',
                        count: warn),
                    _LegendDot(
                        color: const Color(0xFFE81123),
                        label: 'Errors',
                        count: err),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthRing extends StatelessWidget {
  const _HealthRing({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SizedBox(
      width: 132,
      height: 132,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: ratio),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _GaugePainter(
              progress: value,
              color: color,
              track: theme.resources.controlStrokeColorDefault,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(value * 100).round()}%',
                    style: theme.typography.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('healthy',
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorTertiary,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [color.withValues(alpha: 0.55), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dim = count == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: dim ? color.withValues(alpha: 0.35) : color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text('$count ',
            style: theme.typography.bodyStrong?.copyWith(
              color: dim ? theme.resources.textFillColorTertiary : null,
            )),
        Text(label,
            style: theme.typography.body?.copyWith(
              color: theme.resources.textFillColorSecondary,
            )),
      ],
    );
  }
}

/// A slim, one-line check row that expands inline to reveal detail lines.
class _CheckRow extends StatefulWidget {
  const _CheckRow({
    required this.section,
    required this.expanded,
    required this.onTap,
  });

  final DoctorSection section;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_CheckRow> createState() => _CheckRowState();
}

class _CheckRowState extends State<_CheckRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final section = widget.section;
    final v = _visualsFor(section.status);
    final hasDetails = section.details.isNotEmpty;
    final primary = _shortTitle(section.title);
    final secondary = _parenthetical(section.title);

    return MouseRegion(
      cursor: hasDetails
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: hasDetails ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover || widget.expanded
                ? theme.resources.subtleFillColorSecondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(v.icon, size: 18, color: v.color),
                  const SizedBox(width: 12),
                  Text(primary, style: theme.typography.bodyStrong),
                  const SizedBox(width: 10),
                  // Fills the middle so the trailing chevron is always pinned to
                  // the right edge, keeping every row's arrow vertically aligned.
                  Expanded(
                    child: secondary == null
                        ? const SizedBox.shrink()
                        : Text(
                            secondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.caption?.copyWith(
                              color: theme.resources.textFillColorTertiary,
                            ),
                          ),
                  ),
                  SizedBox(
                    width: 16,
                    child: hasDetails
                        ? AnimatedRotation(
                            turns: widget.expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: Icon(FluentIcons.chevron_down,
                                size: 10,
                                color: theme.resources.textFillColorSecondary),
                          )
                        : null,
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: hasDetails && widget.expanded
                    ? Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 10, left: 30),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: v.color, width: 2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in section.details)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: SelectableText(
                                  line,
                                  style: theme.typography.caption?.copyWith(
                                    fontFamily: 'Consolas',
                                    color: theme
                                        .resources.textFillColorSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Title text before the first parenthesis, e.g. "Flutter".
  String _shortTitle(String title) {
    final i = title.indexOf('(');
    return (i > 0 ? title.substring(0, i) : title).trim();
  }

  /// The parenthetical descriptor, e.g. "Channel stable, 3.44.1, on …".
  String? _parenthetical(String title) {
    final match = RegExp(r'\(([^)]*)\)').firstMatch(title);
    return match?.group(1)?.trim();
  }

  _Visuals _visualsFor(DoctorStatus status) => switch (status) {
        DoctorStatus.ok => const _Visuals(
            FluentIcons.completed_solid, Color(0xFF3DDC84)),
        DoctorStatus.warning =>
          const _Visuals(FluentIcons.warning, Color(0xFFFFB900)),
        DoctorStatus.error =>
          const _Visuals(FluentIcons.status_error_full, Color(0xFFE81123)),
        DoctorStatus.info =>
          const _Visuals(FluentIcons.info, Color(0xFF767676)),
      };
}

class _Visuals {
  const _Visuals(this.icon, this.color);
  final IconData icon;
  final Color color;
}

// ---- Non-result states ------------------------------------------------------

class _StartView extends StatelessWidget {
  const _StartView({required this.onRun});

  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.accentColor.withValues(alpha: 0.25),
                    theme.accentColor.withValues(alpha: 0.08),
                  ],
                ),
              ),
              child:
                  Icon(FluentIcons.health, size: 40, color: theme.accentColor),
            ),
            const SizedBox(height: 22),
            Text('Check your Flutter environment',
                textAlign: TextAlign.center, style: theme.typography.subtitle),
            const SizedBox(height: 8),
            Text(
              'Runs "flutter doctor -v" and scores your toolchain so you can '
              'spot what needs fixing at a glance.',
              textAlign: TextAlign.center,
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRun,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.play, size: 14),
                    SizedBox(width: 8),
                    Text('Run diagnostics'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressRing(),
          SizedBox(height: 14),
          Text('Running flutter doctor…'),
          SizedBox(height: 4),
          Text('This can take a moment on the first run.',
              style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.error_badge,
                size: 40, color: Color(0xFFE81123)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
