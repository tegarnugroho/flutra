import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/windows/windows_cubit.dart';
import '../../core/di/injection.dart';
import '../../core/platform/platform_service.dart';
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
import 'widgets/requirement_tile.dart';
import 'widgets/windows_identity_panel.dart';

/// Windows toolchain: everything a Flutter Windows desktop build needs.
///
/// Windows-only, and guarded here as well as at the navigation pane — a route
/// reached some other way must not render a page about a toolchain the host
/// cannot have.
class WindowsToolchainPage extends StatelessWidget {
  const WindowsToolchainPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!getIt<PlatformService>().isWindows) {
      return const PageScaffold(
        title: 'Windows toolchain',
        child: EmptyState(
          icon: FluentIcons.blocked2,
          title: 'Windows only',
          message:
            'Visual Studio Build Tools and the Windows SDK exist only on '
            'Windows.',
        ),
      );
    }
    return BlocProvider(
      create: (_) => getIt<WindowsCubit>()..load(),
      child: const _WindowsToolchainView(),
    );
  }
}

class _WindowsToolchainView extends StatefulWidget {
  const _WindowsToolchainView();

  @override
  State<_WindowsToolchainView> createState() => _WindowsToolchainViewState();
}

class _WindowsToolchainViewState extends State<_WindowsToolchainView>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();

  /// Anchors for "Fix issues", one per requirement that has a tile.
  final Map<WindowsRequirementKind, GlobalKey> _anchors = {
    for (final kind in WindowsRequirementKind.values) kind: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  /// The user left to click through Microsoft's installer or to flip a switch
  /// in Settings; coming back is the signal that something may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<WindowsCubit>().refreshOnFocus();
    }
  }

  void _scrollToFirstIssue(WindowsState state) {
    final first = state.toolchain.unmet.firstOrNull;
    if (first == null) return;
    final anchor = _anchors[first.kind]?.currentContext;
    if (anchor == null) return;
    Scrollable.ensureVisible(
      anchor,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.1,
    );
  }

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
          title: 'Windows toolchain',
          titleMeta: state.toolchain.installs.isEmpty
              ? null
              : state.toolchain.summary,
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
                onInstall: () => _run(
                  context,
                  cubit,
                  toolchain.requirements.first,
                ),
                onFixIssues: () => _scrollToFirstIssue(state),
              ),
              if (state.setup != null) ...[
                const SizedBox(height: 10),
                _SetupLine(event: state.setup!, onDismiss: cubit.dismissSetup),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(child: _list(context, state, cubit)),
      ],
    );
  }

  Widget _list(BuildContext context, WindowsState state, WindowsCubit cubit) {
    final toolchain = state.toolchain;
    final others = toolchain.otherInstalls;

    return ListView(
      controller: _scroll,
      padding: kPageBodyPadding,
      children: [
        const SectionLabel('Requirements'),
        const SizedBox(height: 8),
        for (final requirement in toolchain.requirements) ...[
          RequirementTile(
            key: _anchors[requirement.kind],
            requirement: requirement,
            busy: state.isBusy,
            pending: state.pending == requirement.kind,
            trailingPath:
                requirement.kind == WindowsRequirementKind.cppToolchain
                ? toolchain.active?.installPath
                : null,
            onAction: () => _run(context, cubit, requirement),
          ),
          const SizedBox(height: TileBox.gap),
        ],
        if (toolchain.active != null) ...[
          const SizedBox(height: 12),
          const SectionLabel('Maintenance'),
          const SizedBox(height: 8),
          GroupedList(
            children: [
              GroupedListRow(
                title: 'Update ${toolchain.active!.displayName}',
                subtitle:
                    'Runs the Visual Studio Installer\'s update, which decides '
                    'whether anything is newer.',
                trailing: [
                  OutlinedActionButton(
                    icon: FluentIcons.sync,
                    label: 'Update',
                    dense: true,
                    onPressed: state.isBusy
                        ? null
                        : () => _confirmAndUpdate(
                            context,
                            cubit,
                            toolchain.active!,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 12),
          _OtherInstalls(installs: others),
        ],
      ],
    );
  }

  // TODO: update-available detection via VS Installer channel manifest. The
  // installer decides for itself whether an update exists, so the button is
  // always offered rather than shown conditionally on a version comparison
  // the manifest would be needed for.

  /// Every installer launch goes through the same explain-then-run path.
  Future<void> _run(
    BuildContext context,
    WindowsCubit cubit,
    WindowsRequirement requirement,
  ) async {
    final action = requirement.action;
    // The two that touch nothing: no dialog, no installer, no waiting.
    if (action == WindowsRequirementAction.openDeveloperSettings ||
        action == WindowsRequirementAction.enableWindowsDesktop) {
      await cubit.runAction(requirement);
      return;
    }

    final ok = await showConfirmDialog(
      context,
      title: _dialogTitle(action),
      message: _dialogMessage(action),
      confirmLabel: 'Continue',
      destructive: false,
    );
    if (!ok) return;
    await cubit.runAction(requirement);
  }

  Future<void> _confirmAndUpdate(
    BuildContext context,
    WindowsCubit cubit,
    VisualStudioInstall install,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Update ${install.displayName}',
      message: _handover(
        'Runs the Visual Studio Installer\'s update for this install.',
      ),
      confirmLabel: 'Continue',
      destructive: false,
    );
    if (ok) await cubit.update(install);
  }

  static String _dialogTitle(WindowsRequirementAction action) =>
      switch (action) {
        WindowsRequirementAction.installBuildTools =>
          'Install Visual Studio Build Tools',
        WindowsRequirementAction.addCppWorkload => 'Add the C++ workload',
        WindowsRequirementAction.addWindowsSdk => 'Add the Windows SDK',
        WindowsRequirementAction.repair => 'Repair the installation',
        _ => 'Run the Visual Studio Installer',
      };

  static String _dialogMessage(WindowsRequirementAction action) =>
      switch (action) {
        WindowsRequirementAction.installBuildTools => _handover(
          'Downloads Microsoft\'s official Build Tools installer and runs it '
          'with the C++ desktop workload, which brings the compiler and a '
          'Windows SDK. It needs several GB.',
        ),
        WindowsRequirementAction.addCppWorkload => _handover(
          'Adds the C++ desktop workload to the Visual Studio already on this '
          'machine. It needs several GB.',
        ),
        WindowsRequirementAction.addWindowsSdk => _handover(
          'Adds the Windows SDK component to the existing install.',
        ),
        WindowsRequirementAction.repair => _handover(
          'Asks the Visual Studio Installer to finish the interrupted '
          'installation.',
        ),
        _ => _handover('Hands over to the Visual Studio Installer.'),
      };

  /// The same three facts every launch has to state.
  static String _handover(String what) =>
      '$what\n\nMicrosoft\'s installer takes over from here and shows its own '
      'progress in its own window. Windows will ask for administrator '
      'permission. Flutra waits and re-checks when it finishes.';
}

/// Installs that are not the one in use — informational, never actionable.
class _OtherInstalls extends StatefulWidget {
  const _OtherInstalls({required this.installs});

  final List<VisualStudioInstall> installs;

  @override
  State<_OtherInstalls> createState() => _OtherInstallsState();
}

class _OtherInstallsState extends State<_OtherInstalls> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Text(
                  'Other installs (${widget.installs.length})',
                  style: text.sectionLabel,
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    FluentIcons.chevron_down,
                    size: 11,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          GroupedList(
            children: [
              for (final install in widget.installs)
                GroupedListRow(
                  title: install.displayName,
                  secondary: install.version,
                  subtitle: install.installPath,
                  trailing: [
                    Text(
                      install.hasCppTools ? 'has C++ tools' : 'no C++ tools',
                      style: text.inlineNote,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
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
    final stage = event.stage;
    final failed = stage == WindowsSetupStage.failed;
    final restart = stage == WindowsSetupStage.restartRequired;

    final colour = failed
        ? palette.statusError
        : restart
        ? palette.statusWarn
        : stage == WindowsSetupStage.done
        ? palette.statusOk
        : palette.textSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          failed
              ? FluentIcons.error_badge
              : restart
              ? FluentIcons.warning
              : stage == WindowsSetupStage.done
              ? FluentIcons.check_mark
              : FluentIcons.info,
          size: 13,
          color: colour,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            event.error ??
                (restart
                    ? 'Installed. Windows recommends a restart before '
                          'building.'
                    : stage.label),
            style: text.caption.copyWith(color: colour),
          ),
        ),
        if (stage.isTerminal) ...[
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
