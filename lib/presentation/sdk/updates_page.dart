import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/flutter_sdk/flutter_update_cubit.dart';
import '../../application/sdk/sdk_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/sdk_package.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/status_dot.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'widgets/package_progress.dart';

/// Updates: checks the SDK catalogue and lists packages with a newer version,
/// with per-package Update and Update-all. Reuses the shared install queue.
class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<SdkManagerCubit>()..load()),
        BlocProvider(create: (_) => getIt<FlutterUpdateCubit>()..check()),
      ],
      child: const _UpdatesView(),
    );
  }
}

class _UpdatesView extends StatelessWidget {
  const _UpdatesView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SdkManagerCubit, SdkManagerState>(
      builder: (context, state) {
        final cubit = context.read<SdkManagerCubit>();
        return PageScaffold(
          title: 'Updates',
          actions: [
            OutlinedActionButton(
              icon: FluentIcons.sync,
              label:
                  'Update all${state.updateCount > 0 ? ' (${state.updateCount})' : ''}',
              onPressed:
                  state.busy || state.updateCount == 0 ? null : cubit.updateAll,
            ),
            OutlinedActionButton(
              icon: FluentIcons.command_prompt,
              label: 'Console',
              onPressed: cubit.toggleConsole,
            ),
            OutlinedActionButton(
              icon: FluentIcons.refresh,
              label: 'Check for updates',
              busy: state.isLoading,
              onPressed: cubit.load,
            ),
          ],
          child: Column(
            children: [
              Expanded(child: _body(context, state, cubit)),
              if (state.queuedCount > 0 || state.busy)
                PackageQueueBar(state: state, cubit: cubit),
              if (state.consoleVisible)
                PackageConsole(state: state, cubit: cubit),
            ],
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    SdkManagerState state,
    SdkManagerCubit cubit,
  ) {
    if (state.isLoading && state.packages.isEmpty) {
      return const Center(child: ProgressRing());
    }
    if (state.status == SdkManagerStatus.failure && state.packages.isEmpty) {
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Could not check for updates',
        message: state.errorMessage ?? 'Unknown error.',
        actionLabel: 'Retry',
        onAction: cubit.load,
      );
    }

    final palette = AppPalette.of(context);
    final updates = state.packages.where((p) => p.hasUpdate).toList();

    return SingleChildScrollView(
      padding: kPageBodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusLine(
            color: updates.isEmpty ? palette.statusOk : palette.statusWarn,
            message: updates.isEmpty
                ? 'Up to date — all installed SDK packages are on their latest version'
                : '${updates.length} update${updates.length == 1 ? '' : 's'} available',
          ),
          const SizedBox(height: 18),
          const SectionLabel('Flutter SDK'),
          const SizedBox(height: 8),
          const _FlutterUpdateRow(),
          if (updates.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionLabel('Available updates'),
            const SizedBox(height: 8),
            GroupedList(
              children: [
                for (final pkg in updates)
                  _UpdateRow(pkg: pkg, state: state, cubit: cubit),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({
    required this.pkg,
    required this.state,
    required this.cubit,
  });

  final SdkPackage pkg;
  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final active = state.isActive(pkg.path);
    final queued = state.isQueued(pkg.path);

    return GroupedListRow(
      statusColor: palette.statusWarn,
      showStatusSlot: true,
      title: pkg.description,
      secondary: pkg.path,
      trailing: [
        Text.rich(
          TextSpan(
            style: AppTextStyles.monoValue,
            children: [
              TextSpan(text: pkg.installedVersion ?? '?'),
              TextSpan(
                text: ' → ',
                style: AppTextStyles.monoValue.copyWith(
                  color: palette.textMuted,
                ),
              ),
              TextSpan(text: pkg.availableVersion ?? '?'),
            ],
          ),
        ),
        if (queued && !active)
          const Text('queued', style: AppTextStyles.inlineNote),
      ],
      hoverActions: [
        if (!active && !queued)
          OutlinedActionButton(
            icon: FluentIcons.sync,
            label: 'Update',
            dense: true,
            onPressed: () => cubit.enqueueInstall(pkg.path),
          ),
      ],
      below: active ? _progress(context) : null,
    );
  }

  Widget _progress(BuildContext context) {
    final palette = AppPalette.of(context);
    final value = state.progress;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 16),
      child: Row(
        children: [
          Expanded(
            child: ProgressBar(
              value: value != null ? value * 100 : null,
              activeColor: palette.accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value != null ? '${(value * 100).round()}%' : 'Updating…',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

/// The Flutter SDK's own update state, from the official release index.
///
/// Driven by [FlutterUpdateCubit] rather than local state: the check is async
/// and its result outlives a rebuild.
class _FlutterUpdateRow extends StatelessWidget {
  const _FlutterUpdateRow();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return BlocBuilder<FlutterUpdateCubit, FlutterUpdateState>(
      builder: (context, state) {
        final update = state.update;
        if (update == null) {
          return GroupedList(
            children: [
              GroupedListRow(
                title: 'Flutter SDK',
                subtitle: state.isLoading
                    ? 'Checking the release channel…'
                    : 'Could not reach the Flutter release list.',
                trailing: [
                  if (state.isLoading)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2))
                  else
                    OutlinedActionButton(
                      icon: FluentIcons.refresh,
                      label: 'Check again',
                      dense: true,
                      onPressed: () => context
                          .read<FlutterUpdateCubit>()
                          .check(forceRefresh: true),
                    ),
                ],
              ),
            ],
          );
        }

        final latest = update.latest;
        final installed = update.installed;
        return GroupedList(
          children: [
            GroupedListRow(
              statusColor: update.updateAvailable
                  ? palette.statusWarn
                  : palette.statusOk,
              showStatusSlot: true,
              title: 'Flutter SDK',
              secondary: update.channel,
              trailing: [
                if (update.updateAvailable && latest != null)
                  Text.rich(
                    TextSpan(
                      style: AppTextStyles.monoValue,
                      children: [
                        TextSpan(
                            text: installed?.displayVersion ??
                                update.shortHash ??
                                '?'),
                        TextSpan(
                          text: ' → ',
                          style: AppTextStyles.monoValue
                              .copyWith(color: palette.textMuted),
                        ),
                        TextSpan(text: latest.displayVersion),
                      ],
                    ),
                  )
                else
                  Text(installed?.displayVersion ?? update.shortHash ?? '—',
                      style: AppTextStyles.monoValue),
                if (state.isLoading)
                  const SizedBox(
                      width: 14, height: 14, child: ProgressRing(strokeWidth: 2)),
              ],
              hoverActions: [
                if (!state.isLoading)
                  OutlinedActionButton(
                    icon: FluentIcons.refresh,
                    label: 'Check again',
                    dense: true,
                    onPressed: () => context
                        .read<FlutterUpdateCubit>()
                        .check(forceRefresh: true),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
