import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/sdk/reclaim_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/platform/system_actions.dart';
import '../../../domain/entities/reclaimable_item.dart';
import '../../common/app_loader.dart';
import '../../common/command_log_view.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'storage_panel.dart' show formatBytes;

/// Opens the reclaimable-storage flow: review, confirm, remove.
///
/// Resolves to true when anything was actually freed, so the dashboard knows
/// to re-scan its storage figures.
Future<bool> showReclaimDialog(BuildContext context) async {
  final freed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider(
      create: (_) => getIt<ReclaimCubit>()..scan(),
      child: const _ReclaimDialog(),
    ),
  );
  return freed ?? false;
}

class _ReclaimDialog extends StatelessWidget {
  const _ReclaimDialog();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReclaimCubit, ReclaimState>(
      builder: (context, state) {
        final palette = AppPalette.of(context);
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 680),
          title: Row(
            children: [
              Icon(FluentIcons.recycle_bin, size: 16, color: palette.statusWarn),
              const SizedBox(width: 10),
              Expanded(child: Text(_title(state))),
            ],
          ),
          content: switch (state.phase) {
            ReclaimPhase.scanning => const _Scanning(),
            ReclaimPhase.review => _ReviewList(state: state),
            ReclaimPhase.confirm => _Confirm(state: state),
            ReclaimPhase.removing ||
            ReclaimPhase.finished =>
              _Execution(state: state),
          },
          actions: _actions(context, state),
        );
      },
    );
  }

  static String _title(ReclaimState state) => switch (state.phase) {
        ReclaimPhase.scanning => 'Looking for reclaimable storage',
        ReclaimPhase.review => 'Reclaimable storage',
        ReclaimPhase.confirm => 'Confirm removal',
        ReclaimPhase.removing => 'Removing',
        ReclaimPhase.finished => 'Done',
      };

  List<Widget> _actions(BuildContext context, ReclaimState state) {
    final cubit = context.read<ReclaimCubit>();
    return switch (state.phase) {
      ReclaimPhase.scanning => [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ReclaimPhase.review => [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: state.selectedItems.isEmpty ? null : cubit.review,
            child: Text(
              state.selectedBytes > 0
                  ? 'Remove selected · ${formatBytes(state.selectedBytes)}'
                  : 'Remove selected',
            ),
          ),
        ],
      ReclaimPhase.confirm => [
          Button(onPressed: cubit.back, child: const Text('Back')),
          FilledButton(
            onPressed: cubit.remove,
            child: const Text('Confirm remove'),
          ),
        ],
      ReclaimPhase.removing => const [],
      ReclaimPhase.finished => [
          if (state.hasFailures)
            Button(
              onPressed: () {
                // Retry keeps only what failed selected.
                cubit.rescan();
              },
              child: const Text('Re-scan'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(state.freedBytes > 0),
            child: const Text('Close'),
          ),
        ],
    };
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppLoader(size: AppLoaderSize.small),
        const SizedBox(width: 12),
        Text(
          'Reading the installed packages…',
          style: AppTextStyles.of(context).caption,
        ),
      ],
    );
  }
}

/// Phase 1: what could go, grouped by kind.
class _ReviewList extends StatelessWidget {
  const _ReviewList({required this.state});

  final ReclaimState state;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final palette = AppPalette.of(context);
    final report = state.report;

    if (state.errorMessage != null) {
      return Text(
        state.errorMessage!,
        style: text.caption.copyWith(color: palette.statusError),
      );
    }
    if (report == null || report.items.isEmpty) {
      return Text(
        'Nothing to reclaim — every installed package is the newest of its '
        'kind.',
        style: text.caption,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Older versions that a newer one has replaced. Sizes are measured on '
          'disk, not estimated.',
          style: text.caption,
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in report.byKind.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, top: 4),
                    child: Text(entry.key.label, style: text.rowLabel),
                  ),
                  for (final item in entry.value)
                    _ItemRow(
                      item: item,
                      selected: state.selected.contains(item.id),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.selected});

  final ReclaimableItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    final cubit = context.read<ReclaimCubit>();
    final blocked = item.isBlocked;

    return Opacity(
      opacity: blocked ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: MouseRegion(
          cursor: blocked ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: blocked ? null : () => cubit.toggle(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? palette.accentBgTint : palette.sidebarBg,
                borderRadius: BorderRadius.circular(AppShape.radiusControl),
                border: Border.all(
                  color: selected ? palette.accent : palette.border,
                  width: AppShape.hairline,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    blocked
                        ? FluentIcons.blocked2
                        : selected
                            ? FluentIcons.checkbox_composite
                            : FluentIcons.checkbox,
                    size: 14,
                    color: blocked
                        ? palette.textMuted
                        : selected
                            ? palette.accent
                            : palette.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.displayName,
                                style: text.rowTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (item.sizeBytes == null)
                              AppLoader(size: AppLoaderSize.small)
                            else
                              Text(
                                formatBytes(item.sizeBytes!),
                                style: text.monoValue,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          blocked ? item.blockedReason! : item.reason,
                          style: text.caption.copyWith(
                            color: blocked ? palette.statusWarn : null,
                          ),
                        ),
                        for (final warning in item.warnings)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  FluentIcons.warning,
                                  size: 11,
                                  color: palette.statusWarn,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(warning, style: text.caption),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedActionButton(
                    icon: FluentIcons.folder_open,
                    dense: true,
                    tooltip: 'Open ${item.folderPath}',
                    onPressed: () => _openFolder(item.folderPath),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The system file manager at the folder, so the user can look before
  /// deciding.
  void _openFolder(String path) =>
      unawaited(getIt<SystemActions>().revealInFileManager(path));
}

/// Phase 2: exactly what will run, and what it costs.
class _Confirm extends StatelessWidget {
  const _Confirm({required this.state});

  final ReclaimState state;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final palette = AppPalette.of(context);
    final items = state.selectedItems;
    final warnings = <String>{for (final i in items) ...i.warnings};

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${items.length} package${items.length == 1 ? '' : 's'} · '
          '${formatBytes(state.selectedBytes)} to free',
          style: text.rowTitle,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.logBg,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
            border: Border.all(color: palette.border, width: AppShape.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Text('sdkmanager --uninstall "${item.id}"',
                    style: text.monoLog),
            ],
          ),
        ),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(FluentIcons.warning, size: 11, color: palette.statusWarn),
                  const SizedBox(width: 6),
                  Expanded(child: Text(warning, style: text.caption)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Phase 3: per-item progress over the live log.
class _Execution extends StatelessWidget {
  const _Execution({required this.state});

  final ReclaimState state;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final palette = AppPalette.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final item in state.selectedItems)
              _StatusChip(
                label: item.displayName,
                status: state.statuses[item.id] ?? ReclaimItemStatus.pending,
              ),
          ],
        ),
        const SizedBox(height: 12),
        LogLinesView(
          lines: state.lines,
          height: 240,
          starting: state.isRemoving,
        ),
        if (state.isFinished) ...[
          const SizedBox(height: 12),
          InfoBar(
            title: Text(
              state.freedBytes > 0
                  ? 'Freed ${formatBytes(state.freedBytes)}'
                  : 'Nothing was removed',
            ),
            content: Text(
              state.hasFailures
                  ? '${state.failedItems.length} item(s) could not be removed '
                      '— close anything using them and try again.'
                  : 'The packages are gone and the SDK is up to date.',
            ),
            severity: state.hasFailures
                ? InfoBarSeverity.warning
                : InfoBarSeverity.success,
            isLong: true,
          ),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            state.errorMessage!,
            style: text.caption.copyWith(color: palette.statusError),
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.status});

  final String label;
  final ReclaimItemStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    final (icon, color) = switch (status) {
      ReclaimItemStatus.pending => (FluentIcons.more, palette.textMuted),
      ReclaimItemStatus.running => (FluentIcons.sync, palette.accent),
      ReclaimItemStatus.done => (FluentIcons.completed_solid, palette.statusOk),
      ReclaimItemStatus.failed => (FluentIcons.error_badge, palette.statusError),
      ReclaimItemStatus.skipped => (FluentIcons.blocked2, palette.statusWarn),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 6),
          Text(label, style: text.badge.copyWith(color: color)),
        ],
      ),
    );
  }
}
