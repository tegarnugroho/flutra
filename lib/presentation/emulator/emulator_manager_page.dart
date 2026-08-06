import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/emulator/emulator_events.dart';
import '../../application/emulator/emulator_list_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/avd.dart';
import '../../domain/entities/avd_create_request.dart';
import '../common/confirm_dialog.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../window/task_windows.dart';
import 'widgets/avd_row.dart';

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

  /// The console goes through the shared opener like every other task window,
  /// so it gets the warm path, the frame and the debounce too.
  Future<void> _openConsoleWindow(Avd avd) =>
      openEmulatorConsoleWindow(avd.name);

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: _EmulatorManagerView(
        onCreate: openCreateEmulatorWindow,
        onConsole: _openConsoleWindow,
      ),
    );
  }
}

class _EmulatorManagerView extends StatelessWidget {
  const _EmulatorManagerView({required this.onCreate, required this.onConsole});

  final VoidCallback onCreate;
  final void Function(Avd) onConsole;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<EmulatorListCubit, EmulatorListState>(
      listenWhen: (prev, curr) =>
          curr.errorMessage != null && prev.errorMessage != curr.errorMessage,
      listener: (context, state) {
        displayInfoBar(
          context,
          builder: (context, close) {
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
          },
        );
      },
      builder: (context, state) {
        final cubit = context.read<EmulatorListCubit>();
        return PageScaffold(
          title: 'Virtual devices',
          actions: [
            OutlinedActionButton(
              icon: FluentIcons.add,
              label: 'Create device',
              onPressed: onCreate,
            ),
            OutlinedActionButton(
              icon: FluentIcons.refresh,
              label: 'Refresh',
              busy: state.isLoading,
              onPressed: cubit.load,
            ),
          ],
          child: _body(context, state, cubit),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    EmulatorListState state,
    EmulatorListCubit cubit,
  ) {
    return LoadingSwitcher(
      showSkeleton: state.isFirstLoad,
      skeleton: const EmulatorListSkeleton(),
      builder: (context) => _loaded(context, state, cubit),
    );
  }

  Widget _loaded(
    BuildContext context,
    EmulatorListState state,
    EmulatorListCubit cubit,
  ) {
    if (state.status == EmulatorListStatus.failure && state.avds.isEmpty) {
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Could not list emulators',
        message: state.errorMessage ?? 'Unknown error.',
        actionLabel: 'Retry',
        onAction: cubit.load,
      );
    }
    if (state.avds.isEmpty) {
      return EmptyState(
        icon: FluentIcons.cell_phone,
        title: 'No emulators yet',
        message: 'Create your first Android Virtual Device to get started.',
        actionLabel: 'Create device',
        actionIcon: FluentIcons.add,
        onAction: onCreate,
      );
    }
    return SingleChildScrollView(
      padding: kPageBodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Virtual devices', meta: '${state.avds.length}'),
          const SizedBox(height: 8),
          GroupedList(
            children: [
              for (final avd in state.avds)
                AvdRow(
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
                  onConsole: () => onConsole(avd),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmWipe(
    BuildContext context,
    EmulatorListCubit cubit,
    Avd avd,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Wipe "${avd.name}"?',
      message:
          'This clears all user data and snapshots. The emulator will '
          'boot fresh next time. This cannot be undone.',
      confirmLabel: 'Wipe data',
    );
    if (ok) cubit.wipe(avd);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    EmulatorListCubit cubit,
    Avd avd,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete "${avd.name}"?',
      message: 'The AVD and all its data will be permanently removed.',
      confirmLabel: 'Delete',
    );
    if (ok) cubit.delete(avd);
  }

  Future<void> _promptDuplicate(
    BuildContext context,
    EmulatorListCubit cubit,
    Avd avd,
  ) async {
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
