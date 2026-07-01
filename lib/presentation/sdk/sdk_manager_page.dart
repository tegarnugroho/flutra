import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/sdk/sdk_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/sdk_package.dart';
import '../emulator/widgets/avd_dialogs.dart';
import 'widgets/sdk_package_tile.dart';

/// Package Manager: browse, search, install, update and remove Android SDK
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
    final cubit = context.read<SdkManagerCubit>();
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('SDK Manager'),
        commandBar: BlocBuilder<SdkManagerCubit, SdkManagerState>(
          builder: (context, state) => CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.sync),
                label: Text(
                    'Update all${state.updateCount > 0 ? ' (${state.updateCount})' : ''}'),
                onPressed:
                    state.busy || state.updateCount == 0 ? null : cubit.updateAll,
              ),
              CommandBarButton(
                icon: Icon(state.consoleVisible
                    ? FluentIcons.chevron_down
                    : FluentIcons.command_prompt),
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
                label: const Text('Refresh'),
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
                  Text('Querying sdkmanager…'),
                ],
              ),
            );
          }
          if (state.status == SdkManagerStatus.failure &&
              state.packages.isEmpty) {
            return _ErrorView(
                message: state.errorMessage ?? 'Unknown error.',
                onRetry: cubit.load);
          }
          return Column(
            children: [
              _Toolbar(state: state, cubit: cubit),
              const Divider(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Sidebar(state: state, cubit: cubit),
                    const Divider(direction: Axis.vertical),
                    Expanded(child: _PackageList(state: state, cubit: cubit)),
                    if (state.selectedPackage != null) ...[
                      const Divider(direction: Axis.vertical),
                      _DetailsPanel(package: state.selectedPackage!, cubit: cubit),
                    ],
                  ],
                ),
              ),
              if (state.queuedCount > 0 || state.busy)
                _QueueBar(state: state, cubit: cubit),
              if (state.consoleVisible) _ConsolePanel(state: state, cubit: cubit),
            ],
          );
        },
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextBox(
              placeholder: 'Search packages…',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(FluentIcons.search, size: 14),
              ),
              onChanged: cubit.setQuery,
            ),
          ),
          SizedBox(
            width: 150,
            child: ComboBox<PackageSort>(
              isExpanded: true,
              value: state.sort,
              items: [
                for (final s in PackageSort.values)
                  ComboBoxItem(value: s, child: Text('Sort: ${s.label}')),
              ],
              onChanged: (v) => v == null ? null : cubit.setSort(v),
            ),
          ),
          ToggleButton(
            checked: state.updatesOnly,
            onChanged: cubit.toggleUpdatesOnly,
            child: const Text('Updates'),
          ),
          ToggleButton(
            checked: state.installedOnly,
            onChanged: cubit.toggleInstalledOnly,
            child: const Text('Installed'),
          ),
          if (state.selected.isNotEmpty) ...[
            const SizedBox(width: 4),
            FilledButton(
              onPressed: state.busy ? null : cubit.installSelected,
              child: Text('Install (${state.selected.length})'),
            ),
            Button(
              onPressed: state.busy
                  ? null
                  : () => _removeSelected(context),
              child: const Text('Remove'),
            ),
            Button(onPressed: cubit.clearChecks, child: const Text('Clear')),
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

// ---- Sidebar ----------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final counts = state.categoryCounts;
    return SizedBox(
      width: 210,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          _CategoryItem(
            label: 'All packages',
            icon: FluentIcons.all_apps,
            count: state.packages.length,
            selected: state.category == null,
            onTap: () => cubit.setCategory(null),
          ),
          const SizedBox(height: 4),
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

class _CategoryItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: selected
              ? theme.accentColor.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: selected
                    ? theme.accentColor
                    : theme.resources.textFillColorSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: theme.typography.body?.copyWith(
                    color: selected ? theme.accentColor : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text('$count',
                style: theme.typography.caption?.copyWith(
                  color: theme.resources.textFillColorTertiary,
                )),
          ],
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Button(
                onPressed: cubit.checkAllVisible,
                child: const Text('Select all'),
              ),
              const Spacer(),
              Text('${packages.length} shown • ${state.installedCount} installed',
                  style: FluentTheme.of(context).typography.caption),
            ],
          ),
        ),
        Expanded(
          child: packages.isEmpty
              ? Center(
                  child: Text('No packages match the current filters.',
                      style: FluentTheme.of(context).typography.body?.copyWith(
                            color: FluentTheme.of(context)
                                .resources
                                .textFillColorSecondary,
                          )),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: packages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final pkg = packages[i];
                    return SdkPackageTile(
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
    final theme = FluentTheme.of(context);
    return SizedBox(
      width: 320,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(package.description, style: theme.typography.subtitle),
            const SizedBox(height: 4),
            Text(package.category.label,
                style: theme.typography.caption?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                )),
            const SizedBox(height: 16),
            _kv(theme, 'Status', _statusLabel),
            _kv(theme, 'Repository path', package.path, mono: true),
            if (package.installedVersion != null)
              _kv(theme, 'Installed version', package.installedVersion!),
            if (package.availableVersion != null)
              _kv(theme, 'Latest version', package.availableVersion!),
            if (package.location != null)
              _kv(theme, 'Location', package.location!, mono: true),
            const SizedBox(height: 16),
            _actions(context),
          ],
        ),
      ),
    );
  }

  String get _statusLabel => switch (package.state) {
        PackageState.installed => 'Installed',
        PackageState.updatable => 'Update available',
        PackageState.available => 'Not installed',
      };

  Widget _actions(BuildContext context) {
    final buttons = <Widget>[];
    if (!package.isInstalled) {
      buttons.add(FilledButton(
          onPressed: () => cubit.enqueueInstall(package.path),
          child: const Text('Install')));
    } else {
      if (package.hasUpdate) {
        buttons.add(FilledButton(
            onPressed: () => cubit.enqueueInstall(package.path),
            child: const Text('Update')));
      }
      buttons.add(Button(
          onPressed: () => cubit.enqueueInstall(package.path),
          child: const Text('Reinstall')));
    }
    buttons.add(Button(
      onPressed: () => _copyPath(context),
      child: const Text('Copy path'),
    ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          buttons[i],
        ],
      ],
    );
  }

  Future<void> _copyPath(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: package.path));
    if (!context.mounted) return;
    await displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('Copied'),
        content: Text(package.path),
        severity: InfoBarSeverity.success,
        onClose: close,
      );
    });
  }

  Widget _kv(FluentThemeData theme, String k, String v, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              )),
          const SizedBox(height: 2),
          SelectableText(v,
              style: mono
                  ? theme.typography.caption
                      ?.copyWith(fontFamily: 'Consolas')
                  : theme.typography.body),
        ],
      ),
    );
  }
}

// ---- Queue bar --------------------------------------------------------------

class _QueueBar extends StatelessWidget {
  const _QueueBar({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        border: Border(
            top: BorderSide(
                color: theme.resources.controlStrokeColorDefault)),
      ),
      child: Row(
        children: [
          const SizedBox(
              width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.activePath ?? 'Working…',
                  style: theme.typography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ProgressBar(
                    value: state.progress != null
                        ? state.progress! * 100
                        : null),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (state.queue.isNotEmpty)
            Text('${state.queue.length} queued',
                style: theme.typography.caption),
          const SizedBox(width: 12),
          Button(onPressed: cubit.cancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

// ---- Console ----------------------------------------------------------------

class _ConsolePanel extends StatefulWidget {
  const _ConsolePanel({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  State<_ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<_ConsolePanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0C),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF161616),
            child: Row(
              children: [
                const Icon(FluentIcons.command_prompt,
                    size: 12, color: Color(0xFFBBBBBB)),
                const SizedBox(width: 8),
                const Text('Console',
                    style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 12)),
                const Spacer(),
                Tooltip(
                  message: 'Clear',
                  child: IconButton(
                    icon: const Icon(FluentIcons.clear, size: 12),
                    onPressed: widget.cubit.clearConsole,
                  ),
                ),
                Tooltip(
                  message: 'Hide',
                  child: IconButton(
                    icon: const Icon(FluentIcons.chevron_down, size: 12),
                    onPressed: widget.cubit.toggleConsole,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(10),
              itemCount: widget.state.console.length,
              itemBuilder: (context, i) {
                final line = widget.state.console[i];
                final isCmd = line.startsWith('\$');
                final isErr = line.startsWith('✗');
                return SelectableText(
                  line,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    height: 1.35,
                    color: isCmd
                        ? const Color(0xFF63E39C)
                        : isErr
                            ? const Color(0xFFFF6B6B)
                            : const Color(0xFFD4D4D4),
                  ),
                );
              },
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.error_badge,
                size: 40, color: Color(0xFFC42B1C)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
