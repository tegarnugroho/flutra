import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/sdk/sdk_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/sdk_package.dart';
import '../common/command_progress_dialog.dart';
import '../emulator/widgets/avd_dialogs.dart';
import 'widgets/sdk_package_tile.dart';

/// SDK Manager: browse, install, update and uninstall SDK components.
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
              onRetry: cubit.load,
            );
          }
          return Column(
            children: [
              _FilterBar(state: state, cubit: cubit),
              const Divider(),
              Expanded(child: _PackageList(state: state)),
            ],
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state, required this.cubit});

  final SdkManagerState state;
  final SdkManagerCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: TextBox(
              placeholder: 'Search packages…',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(FluentIcons.search, size: 14),
              ),
              onChanged: cubit.setQuery,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            child: ComboBox<PackageCategory?>(
              isExpanded: true,
              placeholder: const Text('All categories'),
              value: state.category,
              items: [
                const ComboBoxItem(value: null, child: Text('All categories')),
                for (final c in state.availableCategories)
                  ComboBoxItem(value: c, child: Text(c.label)),
              ],
              onChanged: cubit.setCategory,
            ),
          ),
          const SizedBox(width: 16),
          ToggleButton(
            checked: state.updatesOnly,
            onChanged: cubit.toggleUpdatesOnly,
            child: Text('Updates${state.updateCount > 0 ? ' (${state.updateCount})' : ''}'),
          ),
          const SizedBox(width: 8),
          ToggleButton(
            checked: state.installedOnly,
            onChanged: cubit.toggleInstalledOnly,
            child: const Text('Installed'),
          ),
          const Spacer(),
          Text(
            '${state.filtered.length} shown • ${state.installedCount} installed',
            style: FluentTheme.of(context).typography.caption,
          ),
        ],
      ),
    );
  }
}

class _PackageList extends StatelessWidget {
  const _PackageList({required this.state});

  final SdkManagerState state;

  @override
  Widget build(BuildContext context) {
    final packages = state.filtered;
    if (packages.isEmpty) {
      return Center(
        child: Text(
          'No packages match the current filters.',
          style: FluentTheme.of(context).typography.body?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorSecondary,
              ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: packages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final pkg = packages[i];
        return SdkPackageTile(
          package: pkg,
          onInstall: () => _install(context, pkg),
          onUninstall: () => _uninstall(context, pkg),
        );
      },
    );
  }

  Future<void> _install(BuildContext context, SdkPackage pkg) async {
    final cubit = context.read<SdkManagerCubit>();
    final verb = pkg.hasUpdate ? 'Updating' : 'Installing';
    final ok = await showCommandProgressDialog(
      context,
      title: '$verb ${pkg.path}',
      start: () => cubit.install(pkg.path),
    );
    if (ok) cubit.load();
  }

  Future<void> _uninstall(BuildContext context, SdkPackage pkg) async {
    final cubit = context.read<SdkManagerCubit>();
    final confirm = await showConfirmDialog(
      context,
      title: 'Uninstall ${pkg.path}?',
      message: 'This removes the package from your SDK. You can reinstall it '
          'later from this screen.',
      confirmLabel: 'Uninstall',
    );
    if (!confirm) return;
    if (!context.mounted) return;
    final ok = await showCommandProgressDialog(
      context,
      title: 'Uninstalling ${pkg.path}',
      start: () => cubit.uninstall(pkg.path),
    );
    if (ok) cubit.load();
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
