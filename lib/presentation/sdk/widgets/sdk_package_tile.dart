import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/sdk_package.dart';
import '../../theme/app_colors.dart';

/// A single package row: checkbox, status dot, name/path, version, per-row
/// action, and an inline progress bar while installing.
class SdkPackageTile extends StatelessWidget {
  const SdkPackageTile({
    super.key,
    required this.package,
    required this.checked,
    required this.selected,
    required this.queued,
    required this.active,
    required this.progress,
    required this.onCheck,
    required this.onSelect,
    required this.onInstall,
    required this.onUninstall,
  });

  final SdkPackage package;
  final bool checked;
  final bool selected;
  final bool queued;
  final bool active;
  final double? progress;
  final ValueChanged<bool> onCheck;
  final VoidCallback onSelect;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? theme.accentColor.withValues(alpha: 0.12)
              : theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? theme.accentColor
                : theme.resources.controlStrokeColorDefault,
            width: selected ? 1.4 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  checked: checked,
                  onChanged: (v) => onCheck(v ?? false),
                ),
                const SizedBox(width: 8),
                _statusDot(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(package.description,
                          style: theme.typography.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(package.path,
                          style: theme.typography.caption?.copyWith(
                            fontFamily: 'Consolas',
                            color: theme.resources.textFillColorTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _version(theme),
                const SizedBox(width: 14),
                _action(),
              ],
            ),
            if (active || queued) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ProgressBar(
                      value: active ? (progress != null ? progress! * 100 : null)
                          : 0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    active
                        ? (progress != null
                            ? '${(progress! * 100).round()}%'
                            : 'Working…')
                        : 'Queued',
                    style: theme.typography.caption,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusDot() {
    final color = switch (package.state) {
      PackageState.installed => AppColors.statusOk,
      PackageState.updatable => AppColors.statusWarn,
      PackageState.available => AppColors.textMuted,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _version(FluentThemeData theme) {
    return SizedBox(
      width: 110,
      child: package.hasUpdate
          ? Text(
              '${package.installedVersion ?? '?'} → ${package.availableVersion ?? '?'}',
              style: theme.typography.caption
                  ?.copyWith(color: AppColors.statusWarn),
              textAlign: TextAlign.end,
            )
          : Text(package.displayVersion ?? '—',
              style: theme.typography.caption, textAlign: TextAlign.end),
    );
  }

  Widget _action() {
    if (active || queued) {
      return const SizedBox(width: 84);
    }
    switch (package.state) {
      case PackageState.available:
        return SizedBox(
          width: 84,
          child: FilledButton(
              onPressed: onInstall, child: const Text('Install')),
        );
      case PackageState.updatable:
        return SizedBox(
          width: 84,
          child:
              FilledButton(onPressed: onInstall, child: const Text('Update')),
        );
      case PackageState.installed:
        return SizedBox(
          width: 84,
          child: Tooltip(
            message: 'Uninstall',
            child: IconButton(
              icon: const Icon(FluentIcons.delete, color: AppColors.statusError),
              onPressed: onUninstall,
            ),
          ),
        );
    }
  }
}
