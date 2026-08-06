import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/windows/windows_cubit.dart';
import '../../core/di/injection.dart';
import '../../core/platform/system_actions.dart';
import '../../domain/entities/windows_toolchain.dart';
import '../../infrastructure/windows/windows_toolchain_service.dart';
import '../common/confirm_dialog.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../common/tile_box.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'widgets/vs_install_tile.dart';
import 'widgets/windows_identity_panel.dart';

/// Windows: the MSVC toolchain and Windows SDK a desktop build needs.
class WindowsPage extends StatelessWidget {
  const WindowsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<WindowsCubit>()..load(),
      child: const _WindowsView(),
    );
  }
}

class _WindowsView extends StatelessWidget {
  const _WindowsView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WindowsCubit, WindowsState>(
      listenWhen: (p, c) =>
          c.errorMessage != null && p.errorMessage != c.errorMessage,
      listener: (context, state) {
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('Error'),
            content: Text(state.errorMessage!),
            severity: InfoBarSeverity.error,
            isLong: true,
            onClose: () {
              close();
              context.read<WindowsCubit>().clearError();
            },
          ),
        );
      },
      builder: (context, state) {
        final cubit = context.read<WindowsCubit>();
        return PageScaffold(
          title: 'Windows',
          titleMeta: state.toolchain.installs.isEmpty
              ? null
              : state.toolchain.countLabel,
          actions: [
            OutlinedActionButton(
              icon: FluentIcons.refresh,
              label: 'Refresh',
              busy: state.isLoading,
              onPressed: state.isBusy ? null : () => cubit.load(force: true),
            ),
          ],
          child: LoadingSwitcher(
            showSkeleton: state.isFirstLoad,
            skeleton: const WindowsSkeleton(),
            builder: (context) => _loaded(context, state, cubit),
          ),
        );
      },
    );
  }

  Widget _loaded(BuildContext context, WindowsState state, WindowsCubit cubit) {
    final toolchain = state.toolchain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WindowsIdentityPanel(
                toolchain: toolchain,
                busy: state.isBusy,
                onInstall: () => _confirmInstall(context, cubit),
                onFix: _fixAction(context, state, cubit),
              ),
              if (state.setup != null) ...[
                const SizedBox(height: 10),
                _SetupLine(
                  event: state.setup!,
                  onDismiss: cubit.dismissSetup,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(child: _list(context, state, cubit)),
      ],
    );
  }

  /// The single button the panel offers when something is wrong.
  VoidCallback? _fixAction(
    BuildContext context,
    WindowsState state,
    WindowsCubit cubit,
  ) {
    final toolchain = state.toolchain;
    return switch (toolchain.status) {
      WindowsToolchainStatus.missingCppTools ||
      // No SDK is fixed the same way: the C++ workload brings one with it.
      WindowsToolchainStatus.missingSdk =>
        toolchain.installs.isEmpty
            ? null
            : () => cubit.addCppTools(toolchain.installs.first),
      WindowsToolchainStatus.incomplete => toolchain.installs.isEmpty
          ? null
          : () => cubit.repair(toolchain.installs.first),
      _ => null,
    };
  }

  Widget _list(BuildContext context, WindowsState state, WindowsCubit cubit) {
    final toolchain = state.toolchain;
    if (toolchain.installs.isEmpty) {
      return EmptyState(
        icon: FluentIcons.developer_tools,
        title: 'No build tools found',
        message:
            'Neither Visual Studio nor the standalone Build Tools are on this '
            'machine. Installing Build Tools is enough for Flutter.',
        actionLabel: 'Install Build Tools',
        actionIcon: FluentIcons.download,
        onAction: state.isBusy ? null : () => _confirmInstall(context, cubit),
      );
    }

    return ListView(
      padding: kPageBodyPadding,
      children: [
        const SectionLabel('Build tools'),
        const SizedBox(height: 8),
        for (final install in toolchain.installs) ...[
          VsInstallTile(
            key: ValueKey(install.installPath),
            install: install,
            isActive: install == toolchain.active,
            busy: state.isBusy,
            onAddCppTools: () => cubit.addCppTools(install),
            onUpdate: () => cubit.update(install),
            onRepair: () => cubit.repair(install),
            onShowInFolder: () =>
                getIt<SystemActions>().revealInFileManager(install.installPath),
          ),
          const SizedBox(height: TileBox.gap),
        ],
        if (toolchain.sdks.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionLabel('Windows SDK', meta: '${toolchain.sdks.length}'),
          const SizedBox(height: 8),
          GroupedList(
            children: [
              for (final sdk in toolchain.sdks)
                GroupedListRow(
                  statusColor: sdk == toolchain.newestSdk
                      ? AppPalette.of(context).statusOk
                      : null,
                  showStatusSlot: true,
                  title: sdk.displayVersion,
                  secondary: sdk.version,
                  trailing: [
                    Text(
                      sdk.path,
                      style: AppTextStyles.of(context).monoValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Says what is about to happen before Windows asks for permission.
  static Future<void> _confirmInstall(
    BuildContext context,
    WindowsCubit cubit,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Install Visual Studio Build Tools',
      message:
          'Downloads Microsoft\'s official installer and runs it with the C++ '
          'desktop workload, which brings the compiler and a Windows SDK.\n\n'
          'Windows will ask for administrator permission, and the installer '
          'runs in its own window — it needs several GB and several minutes.',
      confirmLabel: 'Install',
      destructive: false,
    );
    if (ok) await cubit.installBuildTools();
  }
}

/// The installer's progress, and what it left behind.
class _SetupLine extends StatelessWidget {
  const _SetupLine({required this.event, required this.onDismiss});

  final WindowsSetupEvent event;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    final failed = event.stage == WindowsSetupStage.failed;
    final done = event.stage == WindowsSetupStage.done;
    final colour = failed
        ? palette.statusError
        : done
        ? palette.statusOk
        : palette.textSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          failed
              ? FluentIcons.error_badge
              : done
              ? FluentIcons.check_mark
              : FluentIcons.info,
          size: 13,
          color: colour,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            event.error ?? event.stage.label,
            style: text.caption.copyWith(color: colour),
          ),
        ),
        if (failed || done) ...[
          const SizedBox(width: 12),
          OutlinedActionButton(
            icon: FluentIcons.clear,
            dense: true,
            tooltip: 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ],
    );
  }
}
