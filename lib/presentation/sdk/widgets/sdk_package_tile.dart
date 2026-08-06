import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/sdk_package.dart';
import '../../common/compact_field.dart';
import '../../common/status_pill.dart';
import '../../common/tile_box.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The icon standing for a package category, shared by the tile and the
/// category rail so one package never wears two different marks.
IconData packageCategoryIcon(PackageCategory category) => switch (category) {
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

/// One package: what it is, what state it is in, and the one action it takes.
///
/// The checkbox stays for bulk work, but the per-package action is on the tile
/// rather than behind hover — installing one thing is the common case.
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

  /// Whether the details panel is showing this package.
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
    return TileBox(
      onTap: onSelect,
      emphasised: selected || checked,
      outlined: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                AppCheckbox(checked: checked, onChanged: onCheck),
                const SizedBox(width: 10),
                _Mark(package: package),
                const SizedBox(width: 12),
                Expanded(child: _identity(context, palette)),
                const SizedBox(width: 12),
                Flexible(child: _version(context, palette)),
                const SizedBox(width: 10),
                _action(context),
              ],
            ),
            if (active) _progress(context, palette),
          ],
        ),
      ),
    );
  }

  Widget _identity(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                package.description,
                style: text.rowTitle.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Installed is the quiet good state — the icon square already says
            // it. The pill is spent on the two states that want a decision.
            if (package.hasUpdate) ...[
              const SizedBox(width: 8),
              Flexible(
                child: StatusPill(
                  label: 'update available',
                  foreground: palette.statusWarn,
                  background: palette.warnSurface,
                ),
              ),
            ] else if (queued && !active) ...[
              const SizedBox(width: 8),
              Flexible(
                child: StatusPill(
                  label: 'queued',
                  foreground: palette.textMuted,
                  background: palette.surfaceRaised,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            // The path is what sdkmanager takes on the command line, so it is
            // metadata worth reading rather than a suffix on the title.
            Flexible(
              child: Text(
                package.path,
                style: text.monoMeta.copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('·', style: text.caption),
            ),
            Flexible(
              child: Text(
                package.category.label,
                style: text.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _version(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    if (package.hasUpdate) {
      return Text.rich(
        TextSpan(
          style: text.monoValue,
          children: [
            TextSpan(
              text: package.installedVersion ?? '?',
              style: text.monoValue.copyWith(color: palette.textMuted),
            ),
            TextSpan(
              text: ' → ',
              style: text.monoValue.copyWith(color: palette.textMuted),
            ),
            TextSpan(text: package.availableVersion ?? '?'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(
      package.displayVersion ?? '—',
      style: text.monoValue,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _action(BuildContext context) {
    if (active) {
      return OutlinedActionButton(
        icon: FluentIcons.download,
        label: 'Installing…',
        dense: true,
        busy: true,
        onPressed: null,
      );
    }
    if (queued) {
      return const OutlinedActionButton(
        icon: FluentIcons.clock,
        label: 'Queued',
        dense: true,
        onPressed: null,
      );
    }
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
        dangerOnHover: true,
        onPressed: onUninstall,
      ),
    };
  }

  Widget _progress(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
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

/// The category icon in its rounded square, tinted by install state.
class _Mark extends StatelessWidget {
  const _Mark({required this.package});

  final SdkPackage package;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (background, foreground) = switch (package.state) {
      PackageState.installed => (palette.okSurface, palette.statusOk),
      PackageState.updatable => (palette.warnSurface, palette.statusWarn),
      PackageState.available => (palette.surfaceRaised, palette.textSecondary),
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Icon(
        packageCategoryIcon(package.category),
        size: 14,
        color: foreground,
      ),
    );
  }
}
