import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/dashboard/dashboard_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/environment_snapshot.dart';
import '../../domain/entities/tool_status.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../common/status_dot.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
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
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        return PageScaffold(
          title: 'Dashboard',
          actions: [
            OutlinedActionButton(
              icon: FluentIcons.refresh,
              label: 'Refresh',
              busy: state.isLoading,
              onPressed: () =>
                  context.read<DashboardCubit>().refresh(forceRefresh: true),
            ),
          ],
          child: _body(context, state),
        );
      },
    );
  }

  Widget _body(BuildContext context, DashboardState state) {
    if (state.status == DashboardStatus.failure) {
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Detection failed',
        message: state.errorMessage ?? 'Something went wrong.',
        actionLabel: 'Retry',
        onAction: () => context.read<DashboardCubit>().refresh(),
      );
    }
    return LoadingSwitcher(
      showSkeleton: state.snapshot == null,
      skeleton: const DashboardSkeleton(),
      builder: (context) => _DashboardContent(
        snapshot: state.snapshot!,
        lastUpdated: state.lastUpdated,
      ),
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
      padding: kPageBodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusLine(snapshot: snapshot),
          const SizedBox(height: 18),
          const SectionLabel('Toolchain'),
          const SizedBox(height: 8),
          ToolchainList(snapshot: snapshot),
          // Paths moved to Settings > Paths, merged with the override rows.
          if (lastUpdated != null) ...[
            const SizedBox(height: 14),
            Text(
              'Last checked ${_formatTime(lastUpdated!)}',
              style: AppTextStyles.of(context).caption,
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
        .where(
          (t) => t.state == ToolState.missing || t.state == ToolState.error,
        )
        .toList();
    final outdated = tools
        .where((t) => t.state == ToolState.needsUpdate)
        .toList();
    final checking = tools.where((t) => t.state == ToolState.checking).toList();

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
      message =
          'Environment ready — all core Android and Flutter tools detected';
    }

    return StatusLine(color: color, message: message);
  }

  static String _count(int n) => n == 1 ? '1 tool' : '$n tools';

  static String _names(List<ToolStatus> tools) =>
      tools.map((t) => t.displayName).join(', ');
}
