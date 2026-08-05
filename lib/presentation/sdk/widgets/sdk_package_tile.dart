import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/sdk_package.dart';
import '../../common/compact_field.dart';
import '../../common/grouped_list.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// A single package row: checkbox, status dot, name/path, version, hover-only
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
    final palette = AppPalette.of(context);
    return GroupedListRow(
      selected: selected,
      onTap: onSelect,
      statusColor: _statusColor(palette),
      showStatusSlot: true,
      titleWidget: Row(
        children: [
          AppCheckbox(checked: checked, onChanged: onCheck),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: package.description,
                style: AppTextStyles.of(context).rowTitle,
                children: [
                  TextSpan(
                    text: '  ${package.path}',
                    style: AppTextStyles.of(
                      context,
                    ).monoValue.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: [
        _version(palette),
        if (queued && !active)
          Text('queued', style: AppTextStyles.of(context).inlineNote),
      ],
      hoverActions: [if (!active && !queued) _action()],
      below: active ? _progress(palette) : null,
    );
  }

  Color _statusColor(AppPalette palette) => switch (package.state) {
    PackageState.installed => palette.statusOk,
    PackageState.updatable => palette.statusWarn,
    PackageState.available => palette.textMuted,
  };

  Widget _version(AppPalette palette) {
    final text = AppTextStyles.fromPalette(palette);
    if (package.hasUpdate) {
      return Text.rich(
        TextSpan(
          style: text.monoValue,
          children: [
            TextSpan(text: package.installedVersion ?? '?'),
            TextSpan(
              text: ' → ',
              style: text.monoValue.copyWith(color: palette.textMuted),
            ),
            TextSpan(text: package.availableVersion ?? '?'),
          ],
        ),
      );
    }
    return Text(
      package.displayVersion ?? '—',
      style: text.monoValue,
    );
  }

  Widget _action() {
    return switch (package.state) {
      PackageState.available => OutlinedActionButton(
        icon: FluentIcons.download,
        label: 'Install',
        dense: true,
        onPressed: onInstall,
      ),
      PackageState.updatable => OutlinedActionButton(
        icon: FluentIcons.sync,
        label: 'Update',
        dense: true,
        onPressed: onInstall,
      ),
      PackageState.installed => OutlinedActionButton(
        icon: FluentIcons.delete,
        dense: true,
        tooltip: 'Uninstall',
        onPressed: onUninstall,
      ),
    };
  }

  Widget _progress(AppPalette palette) {
    final text = AppTextStyles.fromPalette(palette);
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 16),
      child: Row(
        children: [
          Expanded(
            child: ProgressBar(
              value: progress != null ? progress! * 100 : null,
              activeColor: palette.accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            progress != null ? '${(progress! * 100).round()}%' : 'Working…',
            style: text.caption,
          ),
        ],
      ),
    );
  }
}
