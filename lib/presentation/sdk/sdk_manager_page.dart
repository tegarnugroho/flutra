import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/sdk/sdk_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/sdk_package.dart';
import '../common/compact_field.dart';
import '../common/confirm_dialog.dart';
import '../common/copy_icon_button.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
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

  Widget _body(
    BuildContext context,
    SdkManagerState state,
    SdkManagerCubit cubit,
  ) {
    return LoadingSwitcher(
      showSkeleton: state.isLoading && state.packages.isEmpty,
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
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Could not query the SDK',
        message: state.errorMessage ?? 'Unknown error.',
        actionLabel: 'Retry',
        onAction: cubit.load,
      );
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
              icon: _iconFor(c),
              count: counts[c] ?? 0,
              selected: state.category == c,
              onTap: () => cubit.setCategory(c),
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(PackageCategory c) => switch (c) {
    PackageCategory.platformTools => FluentIcons.plug_connected,
    PackageCategory.buildTools => FluentIcons.build_queue,
    PackageCategory.platforms => FluentIcons.cell_phone,
    PackageCategory.systemImages => FluentIcons.hard_drive,
    PackageCategory.emulator => FluentIcons.devices3,
    PackageCategory.cmdlineTools => FluentIcons.command_prompt,
    PackageCategory.sources => FluentIcons.code,
    PackageCategory.ndk => FluentIcons.developer_tools,
    PackageCategory.extras => FluentIcons.packages,
    PackageCategory.other => FluentIcons.product,
  };
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
              SectionLabel(
                'Packages',
                meta:
                    '${packages.length} shown, '
                    '${state.installedCount} installed',
              ),
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
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: GroupedList(
                    children: [
                      for (final pkg in packages)
                        SdkPackageTile(
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
                        ),
                    ],
                  ),
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
