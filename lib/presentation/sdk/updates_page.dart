import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/sdk/sdk_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/sdk_package.dart';
import 'widgets/package_progress.dart';

/// Updates: checks the SDK catalogue and lists packages with a newer version,
/// with per-package Update and Update-all. Reuses the shared install queue.
class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SdkManagerCubit>()..load(),
      child: const _UpdatesView(),
    );
  }
}

class _UpdatesView extends StatelessWidget {
  const _UpdatesView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SdkManagerCubit>();
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Updates'),
        commandBar: BlocBuilder<SdkManagerCubit, SdkManagerState>(
          builder: (context, state) => CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.sync),
                label: Text(
                    'Update all${state.updateCount > 0 ? ' (${state.updateCount})' : ''}'),
                onPressed: state.busy || state.updateCount == 0
                    ? null
                    : cubit.updateAll,
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.command_prompt),
                label: const Text('Console'),
                onPressed: cubit.toggleConsole,
              ),
              CommandBarButton(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2))
                    : const Icon(FluentIcons.refresh),
                label: const Text('Check for updates'),
                onPressed: state.isLoading ? null : cubit.load,
              ),
            ],
          ),
        ),
      ),
      content: BlocBuilder<SdkManagerCubit, SdkManagerState>(
        builder: (context, state) {
          if (state.isLoading && state.packages.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProgressRing(),
                  SizedBox(height: 12),
                  Text('Checking for updates…'),
                ],
              ),
            );
          }
          if (state.status == SdkManagerStatus.failure &&
              state.packages.isEmpty) {
            return _Message(
              icon: FluentIcons.error_badge,
              iconColor: const Color(0xFFC42B1C),
              title: 'Could not check for updates',
              message: state.errorMessage ?? 'Unknown error.',
              actionLabel: 'Retry',
              onAction: cubit.load,
            );
          }

          final updates =
              state.packages.where((p) => p.hasUpdate).toList();
          return Column(
            children: [
              Expanded(
                child: updates.isEmpty
                    ? _Message(
                        icon: FluentIcons.completed_solid,
                        iconColor: const Color(0xFF3DDC84),
                        title: "You're up to date",
                        message:
                            'All installed SDK packages are on their latest '
                            'version.',
                        actionLabel: 'Check again',
                        onAction: cubit.load,
                      )
                    : _UpdateList(updates: updates, state: state, cubit: cubit),
              ),
              if (state.queuedCount > 0 || state.busy)
                PackageQueueBar(state: state, cubit: cubit),
              if (state.consoleVisible)
                PackageConsole(state: state, cubit: cubit),
            ],
          );
        },
      ),
    );
  }
}

class _UpdateList extends StatelessWidget {
  const _UpdateList({
    required this.updates,
    required this.state,
    required this.cubit,
  });

  final List<SdkPackage> updates;
  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: InfoBar(
            title: Text('${updates.length} update(s) available'),
            content: const Text(
                'Update individual packages, or use "Update all" above.'),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            itemCount: updates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final pkg = updates[i];
              final active = state.isActive(pkg.path);
              final queued = state.isQueued(pkg.path);
              return Card(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                              color: Color(0xFFFFB900),
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pkg.description,
                                  style: theme.typography.bodyStrong,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(pkg.path,
                                  style: theme.typography.caption?.copyWith(
                                    fontFamily: 'Consolas',
                                    color:
                                        theme.resources.textFillColorTertiary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${pkg.installedVersion ?? '?'} → ${pkg.availableVersion ?? '?'}',
                          style: theme.typography.caption
                              ?.copyWith(color: const Color(0xFFFFB900)),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 84,
                          child: active || queued
                              ? const SizedBox()
                              : FilledButton(
                                  onPressed: () =>
                                      cubit.enqueueInstall(pkg.path),
                                  child: const Text('Update'),
                                ),
                        ),
                      ],
                    ),
                    if (active || queued) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ProgressBar(
                                value: active && state.progress != null
                                    ? state.progress! * 100
                                    : (active ? null : 0)),
                          ),
                          const SizedBox(width: 10),
                          Text(active ? 'Updating…' : 'Queued',
                              style: theme.typography.caption),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: iconColor),
            const SizedBox(height: 14),
            Text(title, style: theme.typography.subtitle),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.typography.body?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                )),
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
