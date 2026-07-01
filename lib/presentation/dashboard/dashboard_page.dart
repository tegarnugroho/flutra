import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/dashboard/dashboard_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/environment_snapshot.dart';
import 'widgets/status_card.dart';

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
      header: PageHeader(
        title: const Text('Dashboard'),
        commandBar: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) => CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : const Icon(FluentIcons.refresh),
                label: const Text('Refresh'),
                onPressed: state.isLoading
                    ? null
                    : () => context.read<DashboardCubit>().refresh(),
              ),
            ],
          ),
        ),
      ),
      content: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
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
        },
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
    final theme = FluentTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadinessBanner(snapshot: snapshot),
          const SizedBox(height: 20),
          Text('Toolchain', style: theme.typography.subtitle),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid: as many ~320px columns as fit.
              final columns =
                  (constraints.maxWidth / 340).floor().clamp(1, 4);
              final cards = snapshot.all
                  .map((s) => StatusCard(status: s))
                  .toList();
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: (constraints.maxWidth - (columns - 1) * 12) /
                          columns,
                      child: card,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Details', style: theme.typography.subtitle),
          const SizedBox(height: 12),
          _DetailsTable(snapshot: snapshot),
          if (lastUpdated != null) ...[
            const SizedBox(height: 16),
            Text(
              'Last checked ${_formatTime(lastUpdated!)}',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorTertiary,
              ),
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

class _ReadinessBanner extends StatelessWidget {
  const _ReadinessBanner({required this.snapshot});

  final EnvironmentSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ready = snapshot.isReady;
    final missing = snapshot.all.where((t) => !t.isInstalled).length;
    return InfoBar(
      title: Text(ready
          ? 'Your environment is ready'
          : 'Your environment needs attention'),
      content: Text(ready
          ? 'All core Android & Flutter tools were detected.'
          : '$missing tool(s) missing or need setup. Use the SDK Installer to fix.'),
      severity: ready ? InfoBarSeverity.success : InfoBarSeverity.warning,
      isLong: true,
    );
  }
}

class _DetailsTable extends StatelessWidget {
  const _DetailsTable({required this.snapshot});

  final EnvironmentSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      ('Android SDK Path', snapshot.sdkPath),
      ('Java Path', snapshot.javaPath),
      ('Flutter Path', snapshot.flutterPath),
      ('Platform Tools Version', snapshot.platformToolsVersion),
      ('Build Tools Version', snapshot.buildToolsVersion),
      ('Emulator Version', snapshot.emulatorVersion),
    ];
    return Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(),
            _DetailRow(label: rows[i].$1, value: rows[i].$2),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(label, style: theme.typography.bodyStrong),
          ),
          Expanded(
            child: Text(
              value?.isNotEmpty == true ? value! : '—',
              style: theme.typography.body?.copyWith(
                color: value == null
                    ? theme.resources.textFillColorTertiary
                    : null,
              ),
            ),
          ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.error_badge, size: 40, color: Color(0xFFE81123)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
