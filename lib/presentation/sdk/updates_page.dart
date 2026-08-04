import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/sdk/sdk_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/flutter_update_status.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../../infrastructure/flutter/flutter_update_service.dart';
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
/// Kept out of [SdkManagerCubit], which only knows about Android SDK packages.
class _FlutterUpdateRow extends StatefulWidget {
  const _FlutterUpdateRow();

  @override
  State<_FlutterUpdateRow> createState() => _FlutterUpdateRowState();
}

class _FlutterUpdateRowState extends State<_FlutterUpdateRow> {
  late Future<FlutterUpdateStatus?> _status;

  @override
  void initState() {
    super.initState();
    _status = _check();
  }

  Future<FlutterUpdateStatus?> _check({bool forceRefresh = false}) async {
    try {
      final info = await getIt<FlutterRepository>().getSdkInfo();
      return getIt<FlutterUpdateService>()
          .check(channel: info.channel, forceRefresh: forceRefresh);
    } catch (_) {
      // No Flutter SDK installed, or it isn't readable.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder<FlutterUpdateStatus?>(
      future: _status,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const GroupedList(
            children: [
              GroupedListRow(
                title: 'Flutter SDK',
                subtitle: 'Checking the release channel…',
              ),
            ],
          );
        }
        final status = snapshot.data;
        if (status == null) {
          return const GroupedList(
            children: [
              GroupedListRow(
                title: 'Flutter SDK',
                subtitle: 'Could not reach the Flutter release list.',
              ),
            ],
          );
        }
        final latest = status.latest;
        final installed = status.installed;
        return GroupedList(
          children: [
            GroupedListRow(
              statusColor: status.updateAvailable
                  ? palette.statusWarn
                  : palette.statusOk,
              showStatusSlot: true,
              title: 'Flutter SDK',
              secondary: status.channel,
              trailing: [
                if (status.updateAvailable && latest != null)
                  Text.rich(
                    TextSpan(
                      style: AppTextStyles.monoValue,
                      children: [
                        TextSpan(
                            text: installed?.displayVersion ??
                                status.shortHash ??
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
                  Text(installed?.displayVersion ?? status.shortHash ?? '—',
                      style: AppTextStyles.monoValue),
              ],
              hoverActions: [
                OutlinedActionButton(
                  icon: FluentIcons.refresh,
                  label: 'Check again',
                  dense: true,
                  onPressed: () => setState(
                      () => _status = _check(forceRefresh: true)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
