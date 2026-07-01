import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/emulator/emulator_events.dart';
import '../../application/emulator/emulator_list_cubit.dart';
import '../../application/settings/theme_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/avd.dart';
import '../../domain/entities/avd_create_request.dart';
import '../../main.dart' show kCreateEmulatorWindow;
import 'widgets/avd_card.dart';
import 'widgets/avd_dialogs.dart';

/// Emulator Manager: lists AVDs and exposes launch / lifecycle actions.
///
/// Create Emulator opens in a separate OS window (via desktop_multi_window). The
/// list reloads when this window regains focus or an [EmulatorEvents] change is
/// signalled, keeping both windows in sync.
class EmulatorManagerPage extends StatefulWidget {
  const EmulatorManagerPage({super.key});

  @override
  State<EmulatorManagerPage> createState() => _EmulatorManagerPageState();
}

class _EmulatorManagerPageState extends State<EmulatorManagerPage> {
  late final EmulatorListCubit _cubit;
  StreamSubscription<void>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _cubit = getIt<EmulatorListCubit>()..load();
    _eventsSub = getIt<EmulatorEvents>().onChanged.listen((_) => _cubit.load());
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _cubit.close();
    super.dispose();
  }

  Future<void> _openCreateWindow() async {
    final dark = getIt<ThemeCubit>().state == ThemeMode.dark;
    await WindowController.create(WindowConfiguration(
      arguments: jsonEncode({
        'businessId': kCreateEmulatorWindow,
        'dark': dark,
      }),
      // Show immediately from native so visibility doesn't depend on
      // window_manager being available.
      hiddenAtLaunch: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: _EmulatorManagerView(onCreate: _openCreateWindow),
    );
  }
}

class _EmulatorManagerView extends StatelessWidget {
  const _EmulatorManagerView({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EmulatorListCubit>();
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Emulator Manager'),
        commandBar: BlocBuilder<EmulatorListCubit, EmulatorListState>(
          builder: (context, state) => CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.add),
                label: const Text('Create'),
                onPressed: onCreate,
              ),
              CommandBarButton(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2))
                    : const Icon(FluentIcons.refresh),
                label: const Text('Refresh'),
                onPressed: state.isLoading ? null : cubit.load,
              ),
            ],
          ),
        ),
      ),
      content: BlocConsumer<EmulatorListCubit, EmulatorListState>(
        listenWhen: (prev, curr) =>
            curr.errorMessage != null && prev.errorMessage != curr.errorMessage,
        listener: (context, state) {
          displayInfoBar(context, builder: (context, close) {
            return InfoBar(
              title: const Text('Error'),
              content: Text(state.errorMessage!),
              severity: InfoBarSeverity.error,
              isLong: true,
              onClose: () {
                close();
                context.read<EmulatorListCubit>().clearError();
              },
            );
          });
        },
        builder: (context, state) {
          if (state.status == EmulatorListStatus.loading &&
              state.avds.isEmpty) {
            return const Center(child: ProgressRing());
          }
          if (state.status == EmulatorListStatus.failure &&
              state.avds.isEmpty) {
            return _EmptyOrError(
              icon: FluentIcons.error_badge,
              title: 'Could not list emulators',
              message: state.errorMessage ?? 'Unknown error.',
              actionLabel: 'Retry',
              onAction: cubit.load,
            );
          }
          if (state.avds.isEmpty) {
            return _EmptyOrError(
              icon: FluentIcons.cell_phone,
              title: 'No emulators yet',
              message: 'Create your first Android Virtual Device to get started.',
              actionLabel: 'Create emulator',
              onAction: onCreate,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: state.avds.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final avd = state.avds[i];
              return AvdCard(
                avd: avd,
                busy: state.isBusy(avd.name),
                onLaunch: () => cubit.launch(avd),
                onColdBoot: () => cubit.launch(
                  avd,
                  options: const LaunchOptions(coldBoot: true),
                ),
                onStop: () => cubit.stop(avd),
                onWipe: () => _confirmWipe(context, cubit, avd),
                onDelete: () => _confirmDelete(context, cubit, avd),
                onDuplicate: () => _promptDuplicate(context, cubit, avd),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmWipe(
      BuildContext context, EmulatorListCubit cubit, Avd avd) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Wipe "${avd.name}"?',
      message: 'This clears all user data and snapshots. The emulator will '
          'boot fresh next time. This cannot be undone.',
      confirmLabel: 'Wipe data',
    );
    if (ok) cubit.wipe(avd);
  }

  Future<void> _confirmDelete(
      BuildContext context, EmulatorListCubit cubit, Avd avd) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete "${avd.name}"?',
      message: 'The AVD and all its data will be permanently removed.',
      confirmLabel: 'Delete',
    );
    if (ok) cubit.delete(avd);
  }

  Future<void> _promptDuplicate(
      BuildContext context, EmulatorListCubit cubit, Avd avd) async {
    final name = await showTextPromptDialog(
      context,
      title: 'Duplicate "${avd.name}"',
      label: 'New AVD name',
      initialValue: '${avd.name}_copy',
      confirmLabel: 'Duplicate',
    );
    if (name != null) cubit.duplicate(avd, name);
  }
}

class _EmptyOrError extends StatelessWidget {
  const _EmptyOrError({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.resources.textFillColorTertiary),
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
