import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/dashboard/dashboard_cubit.dart';
import '../../application/shell/shell_navigator.dart';
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
import '../../domain/entities/storage_report.dart';
import '../window/task_windows.dart';
import 'widgets/stat_cards.dart';
import 'widgets/storage_panel.dart';
import 'widgets/toolchain_list.dart';

/// The dashboard screen: an at-a-glance health view of the toolchain.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<DashboardCubit>()..load(),
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
        state: state,
        lastUpdated: state.lastUpdated,
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.snapshot,
    required this.state,
    this.lastUpdated,
  });

  final EnvironmentSnapshot snapshot;
  final DashboardState state;
  final DateTime? lastUpdated;

  /// The dashboard surfaces findings; the screen that owns the delete does the
  /// deleting. This only routes.
  // TODO(filter): the destination could pre-filter to `finding.target` once
  // the SDK manager and AVD list accept an incoming query.
  void _review(BuildContext context, ReclaimableFinding finding) {
    getIt<ShellNavigator>().go(switch (finding.kind) {
      ReclaimableKind.unusedSystemImage ||
      ReclaimableKind.oldBuildTools => ShellDestination.sdkManager,
      ReclaimableKind.staleAvd => ShellDestination.virtualDevices,
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: kPageBodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusLine(snapshot: snapshot),
          const SizedBox(height: 14),
          _StatCards(state: state),
          const SizedBox(height: 14),
          const SectionLabel('Toolchain'),
          const SizedBox(height: 8),
          ToolchainList(snapshot: snapshot),
          const SizedBox(height: 14),
          StoragePanel(
            report: state.storage,
            scanning: state.scanning,
            onAnalyze: () => context.read<DashboardCubit>().analyzeStorage(),
            onReview: (finding) => _review(context, finding),
          ),
          const SizedBox(height: 14),
          _QuickActions(state: state),
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

/// The four numbers worth a glance, 4-up and 2×2 once it gets tight.
class _StatCards extends StatelessWidget {
  const _StatCards({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final stats = state.stats;
    if (stats == null) return const StatCardsSkeleton();

    final storage = state.storage;
    final reclaimable = storage?.reclaimableBytes ?? 0;

    final cards = <Widget>[
      StatCard(
        label: kStatDiskUsed,
        value: storage == null ? '—' : formatBytes(storage.totalBytes),
        subtitle: reclaimable > 0
            ? '${formatBytes(reclaimable)} reclaimable'
            : 'across SDKs & AVDs',
        subtitleColor: reclaimable > 0 ? palette.statusWarn : null,
        onTap: () => Scrollable.ensureVisible(context),
      ),
      StatCard(
        label: kStatVirtualDevices,
        value: '${stats.avdCount}',
        subtitle: stats.runningAvdCount > 0
            ? '${stats.runningAvdCount} running'
            : 'none running',
        onTap: () =>
            getIt<ShellNavigator>().go(ShellDestination.virtualDevices),
      ),
      StatCard(
        label: kStatUpdates,
        value: '${stats.updateCount}',
        valueColor: stats.updateCount > 0 ? palette.accent : null,
        subtitle: stats.updateCount > 0 ? 'available' : 'up to date',
        onTap: () => getIt<ShellNavigator>().go(ShellDestination.updates),
      ),
      StatCard(
        label: kStatDevices,
        value: '${stats.deviceCount}',
        subtitle: 'connected',
        onTap: () => getIt<ShellNavigator>().go(ShellDestination.devices),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) => GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: constraints.maxWidth < 1000 ? 2 : 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          // Label + value + sub-line plus 10px padding each side. 74 was a
          // guess and clipped the sub-line by 12px.
          mainAxisExtent: kStatCardHeight,
        ),
        children: cards,
      ),
    );
  }
}

/// Shortcuts into the three things people open the app to do.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final stats = state.stats;
    final hasAvds = (stats?.avdCount ?? 0) > 0;
    final running = (stats?.runningAvdCount ?? 0) > 0;
    final count = hasAvds ? 3 : 2;

    return LayoutBuilder(
      builder: (context, constraints) => GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // Two lines of short text each — they fit side by side long before
          // the stat cards do.
          crossAxisCount: constraints.maxWidth < 640 ? 1 : count,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: kQuickActionHeight,
        ),
        children: [
          if (hasAvds)
            QuickAction(
              icon: FluentIcons.play,
              iconColor: palette.statusOk,
              title: running ? 'Emulator running' : 'Launch an emulator',
              subtitle: running ? 'already up' : 'from Virtual devices',
              onTap: () =>
                  getIt<ShellNavigator>().go(ShellDestination.virtualDevices),
            ),
          QuickAction(
            icon: FluentIcons.add,
            title: 'Create emulator',
            subtitle: 'new device',
            onTap: openCreateEmulatorWindow,
          ),
          QuickAction(
            icon: FluentIcons.health,
            title: 'Run flutter doctor',
            subtitle: 'diagnose setup',
            // autoRun: arriving here is a request to run, not just to look.
            onTap: () => getIt<ShellNavigator>().go(
              ShellDestination.flutterDoctor,
              autoRun: true,
            ),
          ),
        ],
      ),
    );
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
