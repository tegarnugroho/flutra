import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/sdk/sdk_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/sdk_package.dart';
import '../../infrastructure/sdk/sdk_bootstrap_service.dart';
import '../common/compact_field.dart';
import '../common/confirm_dialog.dart';
import '../common/copy_icon_button.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../common/tile_box.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'widgets/package_progress.dart';
import 'widgets/sdk_package_tile.dart';

/// SDK manager: browse, search, install, update and remove Android SDK
/// packages with a category sidebar, details panel and streamed console.
class SdkManagerPage extends StatelessWidget {
  const SdkManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SdkManagerCubit>()..load(),
      child: const _SdkManagerView(),
    );
  }
}

class _SdkManagerView extends StatelessWidget {
  const _SdkManagerView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SdkManagerCubit, SdkManagerState>(
      builder: (context, state) {
        final cubit = context.read<SdkManagerCubit>();
        return PageScaffold(
          title: 'SDK manager',
          titleMeta: state.packages.isEmpty ? null : _countLabel(state),
          actions: [
            _QuickSetupButton(state: state, cubit: cubit),
            OutlinedActionButton(
              icon: FluentIcons.sync,
              label:
                  'Update all${state.updateCount > 0 ? ' (${state.updateCount})' : ''}',
              onPressed: state.busy || state.updateCount == 0
                  ? null
                  : cubit.updateAll,
            ),
            OutlinedActionButton(
              icon: FluentIcons.command_prompt,
              label: 'Console',
              onPressed: cubit.toggleConsole,
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

  /// `184 packages · 42 installed · 3 updates`, dropping the segments that
  /// would read as zero.
  static String _countLabel(SdkManagerState state) {
    final total = state.packages.length;
    return [
      '$total package${total == 1 ? '' : 's'}',
      if (state.installedCount > 0) '${state.installedCount} installed',
      if (state.updateCount > 0) '${state.updateCount} updates',
    ].join(' · ');
  }

  Widget _body(
    BuildContext context,
    SdkManagerState state,
    SdkManagerCubit cubit,
  ) {
    return LoadingSwitcher(
      showSkeleton: state.isFirstLoad,
      skeleton: const SdkManagerSkeleton(),
      builder: (context) => _loaded(context, state, cubit),
    );
  }

  Widget _loaded(
    BuildContext context,
    SdkManagerState state,
    SdkManagerCubit cubit,
  ) {
    if (state.status == SdkManagerStatus.failure && state.packages.isEmpty) {
      return _SdkUnavailable(state: state, cubit: cubit);
    }

    final palette = AppPalette.of(context);
    return Column(
      children: [
        _Toolbar(state: state, cubit: cubit),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CategorySidebar(state: state, cubit: cubit),
              Container(width: AppShape.hairline, color: palette.border),
              Expanded(
                child: _PackageList(state: state, cubit: cubit),
              ),
              if (state.selectedPackage != null) ...[
                Container(width: AppShape.hairline, color: palette.border),
                _DetailsPanel(package: state.selectedPackage!, cubit: cubit),
              ],
            ],
          ),
        ),
        if (state.queuedCount > 0 || state.busy)
          PackageQueueBar(state: state, cubit: cubit),
        if (state.consoleVisible) PackageConsole(state: state, cubit: cubit),
      ],
    );
  }
}

// ---- No usable SDK ----------------------------------------------------------

/// What the page shows when the catalogue could not be read.
///
/// Three states, not one error. The old page had a single "could not query the
/// SDK" with a Retry button, which on a machine with no SDK was a dead end:
/// `sdkmanager` lives inside `cmdline-tools`, and `cmdline-tools` is installed
/// by `sdkmanager`. Retry could never break that loop, so the page now offers
/// the action that fits the case it is actually in.
class _SdkUnavailable extends StatelessWidget {
  const _SdkUnavailable({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    if (state.bootstrap != null) {
      return _BootstrapProgress(state: state, cubit: cubit);
    }

    return switch (state.availability) {
      SdkAvailability.noSdk => EmptyState(
        icon: FluentIcons.cloud_download,
        title: 'No Android SDK yet',
        message:
            'Flutra can download the Android command-line tools and set up an '
            'SDK it manages itself — no admin rights, and removing it is '
            'deleting a folder. If you already have one, point Flutra at it '
            'instead.',
        actionLabel: 'Install Android SDK here',
        actionIcon: FluentIcons.download,
        onAction: cubit.bootstrapSdk,
        secondaryActionLabel: 'Locate existing SDK…',
        onSecondaryAction: () => _locate(context),
      ),
      SdkAvailability.sdkFoundNoCmdlineTools => EmptyState(
        icon: FluentIcons.packages,
        title: 'This SDK has no command-line tools',
        message:
            'An Android SDK is here, but the tools Flutra drives it with are '
            'missing. They can be added to it without touching anything else '
            'that is already installed.',
        actionLabel: 'Install cmdline-tools into this SDK',
        actionIcon: FluentIcons.download,
        onAction: cubit.bootstrapSdk,
        secondaryActionLabel: 'Locate a different SDK…',
        onSecondaryAction: () => _locate(context),
      ),
      // sdkmanager is there and ran. Retry is the honest offer, and its own
      // output is the only thing that explains why.
      SdkAvailability.queryFailed || SdkAvailability.ok => EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Could not query the SDK',
        message: state.errorMessage ?? 'Unknown error.',
        actionLabel: 'Retry',
        onAction: cubit.load,
        secondaryActionLabel: 'Locate a different SDK…',
        onSecondaryAction: () => _locate(context),
        footer: state.errorDetail == null || state.errorDetail!.trim().isEmpty
            ? null
            : _ErrorDetail(detail: state.errorDetail!.trim()),
      ),
    };
  }

  Future<void> _locate(BuildContext context) async {
    final picked = await getDirectoryPath(confirmButtonText: 'Select SDK');
    if (picked == null || !context.mounted) return;
    final rejection = await cubit.useExistingSdk(picked);
    if (rejection == null || !context.mounted) return;
    await displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Not an Android SDK'),
        content: Text(rejection),
        severity: InfoBarSeverity.warning,
        onClose: close,
      ),
    );
  }
}

/// sdkmanager's own output, folded away.
///
/// Behind a disclosure rather than in the message: the message says what to do,
/// and a stack of tool output above it would bury that.
class _ErrorDetail extends StatelessWidget {
  const _ErrorDetail({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Expander(
        header: const Text('Details from sdkmanager'),
        content: SelectableText(
          detail,
          style: AppTextStyles.of(context).monoBody.copyWith(
            color: palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The bootstrap, while it runs.
///
/// The same shape as the JDK install progress: one line saying which step, a
/// bar for the step that can report one, and a stop that is a real stop.
class _BootstrapProgress extends StatelessWidget {
  const _BootstrapProgress({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final event = state.bootstrap!;
    final text = AppTextStyles.of(context);

    if (event.stage == SdkBootstrapStage.failed) {
      // A failure that still carries an SDK root got past the download: the
      // tools are on disk and the path is saved, so re-reading the catalogue is
      // the way on. Offering "try again" there would re-download 130 MB to
      // arrive back where it already is.
      final toolsLanded = event.sdkRoot != null;
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Setup did not finish',
        message: event.error ?? 'Unknown error.',
        actionLabel: toolsLanded ? 'Reload packages' : 'Try again',
        actionIcon: toolsLanded ? FluentIcons.refresh : FluentIcons.download,
        onAction: toolsLanded ? cubit.load : cubit.bootstrapSdk,
        secondaryActionLabel: 'Dismiss',
        secondaryActionIcon: FluentIcons.cancel,
        onSecondaryAction: cubit.dismissBootstrap,
      );
    }

    // The one step that is a decision rather than a wait. The licences are
    // Google's terms for the packages about to be downloaded, so this stops and
    // asks instead of answering for the user.
    if (event.stage == SdkBootstrapStage.awaitingLicences) {
      return EmptyState(
        icon: FluentIcons.text_document,
        title: 'Accept the Android SDK licences',
        message:
            'The command-line tools are installed in ${event.sdkRoot}. Before '
            'Flutra downloads platform-tools, Google requires you to accept '
            'the SDK licences — you can read them in full on the Licences page.',
        actionLabel: 'Accept and install platform-tools',
        actionIcon: FluentIcons.accept,
        onAction: cubit.acceptLicencesAndFinish,
        secondaryActionLabel: 'Not now',
        secondaryActionIcon: FluentIcons.cancel,
        onSecondaryAction: cubit.dismissBootstrap,
      );
    }

    final progress = event.progress;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Setting up the Android SDK', style: text.heroTitle),
            const SizedBox(height: 6),
            Text(
              progress == null
                  ? event.stage.label
                  : '${event.stage.label} ${(progress * 100).round()}%',
              textAlign: TextAlign.center,
              style: text.caption,
            ),
            const SizedBox(height: 16),
            ProgressBar(value: progress == null ? null : progress * 100),
            const SizedBox(height: 18),
            OutlinedActionButton(
              icon: FluentIcons.cancel,
              label: 'Cancel',
              onPressed: cubit.cancelBootstrap,
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Toolbar ----------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CompactField(
            width: 220,
            placeholder: 'Search packages',
            onChanged: cubit.setQuery,
          ),
          CompactCombo<PackageSort>(
            width: 150,
            value: state.sort,
            items: [
              for (final s in PackageSort.values)
                CompactComboItem(value: s, label: 'Sort: ${s.label}'),
            ],
            onChanged: cubit.setSort,
          ),
          ToggleChip(
            label: 'Updates',
            checked: state.updatesOnly,
            onChanged: cubit.toggleUpdatesOnly,
          ),
          ToggleChip(
            label: 'Installed',
            checked: state.installedOnly,
            onChanged: cubit.toggleInstalledOnly,
          ),
          if (state.selected.isNotEmpty) ...[
            if (state.installableSelectedCount > 0)
              OutlinedActionButton(
                icon: FluentIcons.download,
                label: 'Install (${state.installableSelectedCount})',
                onPressed: state.busy ? null : cubit.installSelected,
              ),
            if (state.removableSelectedCount > 0)
              OutlinedActionButton(
                icon: FluentIcons.delete,
                label: 'Remove (${state.removableSelectedCount})',
                onPressed: state.busy ? null : () => _removeSelected(context),
              ),
            OutlinedActionButton(
              icon: FluentIcons.clear,
              label: 'Clear',
              onPressed: cubit.clearChecks,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _removeSelected(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove selected packages?',
      message:
          'Uninstalls every checked, installed package. This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (ok) cubit.removeSelected();
  }
}

/// Header action offering one-click installs of common package sets.
class _QuickSetupButton extends StatefulWidget {
  const _QuickSetupButton({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  State<_QuickSetupButton> createState() => _QuickSetupButtonState();
}

class _QuickSetupButtonState extends State<_QuickSetupButton> {
  final _flyout = FlyoutController();

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With no usable SDK there is nothing for the presets to install into —
    // every item in the flyout would fail the same way the page already has.
    // The one useful thing "quick setup" can mean here is the bootstrap, so it
    // routes there rather than opening a menu of dead ends.
    if (widget.state.availability.isBootstrappable) {
      return OutlinedActionButton(
        icon: FluentIcons.toolbox,
        label: 'Quick setup',
        busy: widget.state.isBootstrapping,
        onPressed: widget.state.isBootstrapping
            ? null
            : widget.cubit.bootstrapSdk,
      );
    }

    return FlyoutTarget(
      controller: _flyout,
      child: OutlinedActionButton(
        icon: FluentIcons.toolbox,
        label: 'Quick setup',
        onPressed: () => _flyout.showFlyout(
          builder: (flyoutContext) => MenuFlyout(items: _items(flyoutContext)),
        ),
      ),
    );
  }

  List<MenuFlyoutItemBase> _items(BuildContext flyoutContext) {
    final bt = _latestBuildTools;
    void install(List<String> paths) {
      Navigator.of(flyoutContext).pop();
      _installPreset(paths);
    }

    return [
      MenuFlyoutItem(
        leading: const Icon(FluentIcons.toolbox, size: 14),
        text: const Text('Essential tools'),
        onPressed: () => install(const [
          'platform-tools',
          'emulator',
          'cmdline-tools;latest',
        ]),
      ),
      MenuFlyoutItem(
        leading: const Icon(FluentIcons.plug_connected, size: 14),
        text: const Text('Google USB driver'),
        onPressed: () => install(const ['extras;google;usb_driver']),
      ),
      if (_apis.isNotEmpty) const MenuFlyoutSeparator(),
      for (final api in _apis)
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.cell_phone, size: 14),
          text: Text('Android $api environment'),
          onPressed: () => install([
            'platforms;android-$api',
            'system-images;android-$api;google_apis;x86_64',
            ?bt,
          ]),
        ),
    ];
  }

  bool _has(String path) => widget.state.packages.any((p) => p.path == path);

  String? get _latestBuildTools {
    final bt =
        widget.state.packages
            .where((p) => p.category == PackageCategory.buildTools)
            .map((p) => p.path)
            .toList()
          ..sort();
    return bt.isEmpty ? null : bt.last;
  }

  List<int> get _apis {
    final set = <int>{};
    for (final p in widget.state.packages) {
      if (p.category != PackageCategory.platforms) continue;
      final m = RegExp(r'android-(\d+)').firstMatch(p.path);
      if (m != null) set.add(int.parse(m.group(1)!));
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  void _installPreset(List<String> paths) {
    final present = paths.where(_has).toList();
    if (present.isEmpty) {
      displayInfoBar(
        context,
        builder: (context, close) {
          return InfoBar(
            title: const Text('Nothing to install'),
            content: const Text(
              'These packages were not found. Try Refresh, then retry.',
            ),
            severity: InfoBarSeverity.warning,
            onClose: close,
          );
        },
      );
      return;
    }
    for (final p in present) {
      widget.cubit.enqueueInstall(p);
    }
  }
}

// ---- Category sidebar -------------------------------------------------------

class _CategorySidebar extends StatelessWidget {
  const _CategorySidebar({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final counts = state.categoryCounts;
    return SizedBox(
      width: 196,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          _CategoryItem(
            label: 'All packages',
            icon: FluentIcons.all_apps,
            count: state.packages.length,
            selected: state.category == null,
            onTap: () => cubit.setCategory(null),
          ),
          for (final c in state.availableCategories)
            _CategoryItem(
              label: c.label,
              icon: packageCategoryIcon(c),
              count: counts[c] ?? 0,
              selected: state.category == c,
              onTap: () => cubit.setCategory(c),
            ),
        ],
      ),
    );
  }

}

/// A category filter, styled like a navigation pane item.
class _CategoryItem extends StatefulWidget {
  const _CategoryItem({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: widget.selected || _hovered
                ? palette.surfaceRaised
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 15,
                color: widget.selected
                    ? palette.textPrimary
                    : palette.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: widget.selected
                      ? AppTextStyles.of(context).navItemSelected
                      : AppTextStyles.of(context).navItem,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${widget.count}', style: AppTextStyles.of(context).caption),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Package list -----------------------------------------------------------

class _PackageList extends StatelessWidget {
  const _PackageList({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final packages = state.filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              SectionLabel('Packages', meta: '${packages.length} shown'),
              const Spacer(),
              OutlinedActionButton(
                icon: FluentIcons.check_mark,
                label: 'Select all',
                dense: true,
                onPressed: cubit.checkAllVisible,
              ),
            ],
          ),
        ),
        Expanded(
          child: packages.isEmpty
              ? const EmptyState(
                  icon: FluentIcons.packages,
                  title: 'No packages match',
                  message: 'Adjust the search or filters above.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: packages.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: TileBox.gap),
                  itemBuilder: (context, i) {
                    final pkg = packages[i];
                    return SdkPackageTile(
                      key: ValueKey(pkg.path),
                      package: pkg,
                      checked: state.selected.contains(pkg.path),
                      selected: state.selectedPath == pkg.path,
                      queued: state.isQueued(pkg.path),
                      active: state.isActive(pkg.path),
                      progress: state.progress,
                      onCheck: (_) => cubit.toggleCheck(pkg.path),
                      onSelect: () => cubit.select(pkg.path),
                      onInstall: () => cubit.enqueueInstall(pkg.path),
                      onUninstall: () => _uninstall(context, pkg),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _uninstall(BuildContext context, SdkPackage pkg) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Uninstall ${pkg.path}?',
      message: 'Removes the package from your SDK. You can reinstall it later.',
      confirmLabel: 'Uninstall',
    );
    if (!ok) return;
    // Uninstall streams into the console via the cubit's remove flow.
    cubit
      ..clearChecks()
      ..toggleCheck(pkg.path)
      ..removeSelected();
  }
}

// ---- Details panel ----------------------------------------------------------

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.package, required this.cubit});

  final SdkPackage package;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              package.description,
              style: AppTextStyles.of(context).heroTitle,
            ),
            const SizedBox(height: 4),
            Text(
              package.category.label,
              style: AppTextStyles.of(context).caption,
            ),
            const SizedBox(height: 14),
            const SectionLabel('Details'),
            const SizedBox(height: 8),
            GroupedList(
              children: [
                GroupedListRow(
                  title: 'Status',
                  trailing: [
                    Text(
                      _statusLabel,
                      style: AppTextStyles.of(context).monoValue,
                    ),
                  ],
                ),
                GroupedListRow(
                  title: 'Path',
                  trailing: [
                    Flexible(
                      child: Text(
                        package.path,
                        style: AppTextStyles.of(context).monoValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    CopyIconButton(value: package.path, label: 'Package path'),
                  ],
                ),
                if (package.installedVersion != null)
                  GroupedListRow(
                    title: 'Installed',
                    trailing: [
                      Text(
                        package.installedVersion!,
                        style: AppTextStyles.of(context).monoValue,
                      ),
                    ],
                  ),
                if (package.availableVersion != null)
                  GroupedListRow(
                    title: 'Latest',
                    trailing: [
                      Text(
                        package.availableVersion!,
                        style: AppTextStyles.of(context).monoValue,
                      ),
                    ],
                  ),
                if (package.location != null)
                  GroupedListRow(
                    title: 'Location',
                    trailing: [
                      Flexible(
                        child: Text(
                          package.location!,
                          style: AppTextStyles.of(context).monoValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      CopyIconButton(
                        value: package.location!,
                        label: 'Location',
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!package.isInstalled)
                  OutlinedActionButton(
                    icon: FluentIcons.download,
                    label: 'Install',
                    onPressed: () => cubit.enqueueInstall(package.path),
                  )
                else ...[
                  if (package.hasUpdate)
                    OutlinedActionButton(
                      icon: FluentIcons.sync,
                      label: 'Update',
                      onPressed: () => cubit.enqueueInstall(package.path),
                    ),
                  OutlinedActionButton(
                    icon: FluentIcons.refresh,
                    label: 'Reinstall',
                    onPressed: () => cubit.enqueueInstall(package.path),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _statusLabel => switch (package.state) {
    PackageState.installed => 'installed',
    PackageState.updatable => 'update available',
    PackageState.available => 'not installed',
  };
}
