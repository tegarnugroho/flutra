import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/dashboard/dashboard_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/environment_snapshot.dart';
import '../../domain/entities/tool_status.dart';
import '../common/grouped_list.dart';
import '../common/outlined_action_button.dart';
import '../common/status_dot.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'widgets/paths_list.dart';
import 'widgets/toolchain_list.dart';

/// The dashboard screen: an at-a-glance health view of the toolchain.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<DashboardCubit>()..refresh(),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    const Text('Dashboard', style: AppTextStyles.pageTitle),
                    const Spacer(),
                    OutlinedActionButton(
                      icon: FluentIcons.refresh,
                      label: 'Refresh',
                      busy: state.isLoading,
                      onPressed: () => context.read<DashboardCubit>().refresh(),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body(context, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, DashboardState state) {
    if (state.status == DashboardStatus.failure) {
      return _ErrorView(
        message: state.errorMessage ?? 'Something went wrong.',
        onRetry: () => context.read<DashboardCubit>().refresh(),
      );
    }
    if (state.snapshot == null) {
      return const Center(child: ProgressRing());
    }
    return _DashboardContent(
      snapshot: state.snapshot!,
      lastUpdated: state.lastUpdated,
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.snapshot, this.lastUpdated});

  final EnvironmentSnapshot snapshot;
  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusLine(snapshot: snapshot),
          const SizedBox(height: 18),
          const SectionLabel('Toolchain'),
          const SizedBox(height: 8),
          ToolchainList(snapshot: snapshot),
          const SizedBox(height: 20),
          const SectionLabel('Paths'),
          const SizedBox(height: 8),
          PathsList(snapshot: snapshot),
          if (lastUpdated != null) ...[
            const SizedBox(height: 14),
            Text(
              'Last checked ${_formatTime(lastUpdated!)}',
              style: AppTextStyles.caption,
            ),
          ],
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// One-line readiness summary: a dot plus a sentence, driven entirely by the
/// existing detection state.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.snapshot});

  final EnvironmentSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tools = snapshot.all;

    final broken = tools
        .where((t) =>
            t.state == ToolState.missing || t.state == ToolState.error)
        .toList();
    final outdated =
        tools.where((t) => t.state == ToolState.needsUpdate).toList();
    final checking =
        tools.where((t) => t.state == ToolState.checking).toList();

    final Color color;
    final String message;
    if (broken.isNotEmpty) {
      color = palette.statusError;
      message = '${_count(broken.length)} not detected — ${_names(broken)}';
    } else if (outdated.isNotEmpty) {
      color = palette.statusWarn;
      message = 'Updates available for ${_names(outdated)}';
    } else if (checking.isNotEmpty) {
      color = palette.textMuted;
      message = 'Checking your environment…';
    } else {
      color = palette.statusOk;
      message = 'Environment ready — all core Android and Flutter tools detected';
    }

    return Row(
      children: [
        StatusDot(color: color, size: 7),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.statusLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static String _count(int n) => n == 1 ? '1 tool' : '$n tools';

  static String _names(List<ToolStatus> tools) =>
      tools.map((t) => t.displayName).join(', ');
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.error_badge, size: 24, color: palette.statusError),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.statusLine,
          ),
          const SizedBox(height: 16),
          Button(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
