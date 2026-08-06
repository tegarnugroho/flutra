import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as sys;

import '../../../domain/entities/windows_toolchain.dart';
import '../../common/app_badge.dart';
import '../../common/outlined_action_button.dart';
import '../../common/status_pill.dart';
import '../../common/tile_box.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// One Visual Studio or Build Tools install.
class VsInstallTile extends StatefulWidget {
  const VsInstallTile({
    super.key,
    required this.install,
    required this.isActive,
    required this.busy,
    required this.onAddCppTools,
    required this.onUpdate,
    required this.onRepair,
    required this.onShowInFolder,
  });

  final VisualStudioInstall install;

  /// True for the install a build would pick up.
  final bool isActive;

  /// True while any installer is running — one at a time, machine-wide.
  final bool busy;

  final VoidCallback onAddCppTools;
  final VoidCallback onUpdate;
  final VoidCallback onRepair;
  final VoidCallback onShowInFolder;

  @override
  State<VsInstallTile> createState() => _VsInstallTileState();
}

class _VsInstallTileState extends State<VsInstallTile> {
  final _menu = FlyoutController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    final install = widget.install;

    return TileBox(
      emphasised: widget.isActive,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _Mark(active: widget.isActive),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          install.displayName,
                          style: text.rowTitle.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isActive) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: StatusPill(
                            label: 'in use',
                            foreground: palette.statusOk,
                            background: palette.okSurface,
                          ),
                        ),
                      ],
                      // The two states that break a build, said plainly.
                      if (!install.hasCppTools) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: StatusPill(
                            label: 'no C++ tools',
                            foreground: palette.statusWarn,
                            background: palette.warnSurface,
                          ),
                        ),
                      ],
                      if (!install.isComplete) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: StatusPill(
                            label: 'incomplete',
                            foreground: palette.statusError,
                            background: palette.dangerSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          install.version,
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
                        flex: 3,
                        child: Tooltip(
                          message: install.installPath,
                          child: Text(
                            install.installPath,
                            style: text.monoMeta.copyWith(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (install.isPrerelease) ...[
              const AppBadge('preview'),
              const SizedBox(width: 10),
            ],
            _primaryAction(),
            const SizedBox(width: 6),
            FlyoutTarget(
              controller: _menu,
              child: OutlinedActionButton(
                icon: FluentIcons.more,
                dense: true,
                tooltip: 'More actions',
                onPressed: () => _showMenu(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What this install most needs, as one button.
  Widget _primaryAction() {
    final install = widget.install;
    if (!install.isComplete) {
      return OutlinedActionButton(
        icon: FluentIcons.repair,
        label: 'Repair',
        dense: true,
        warning: true,
        onPressed: widget.busy ? null : widget.onRepair,
      );
    }
    if (!install.hasCppTools) {
      return OutlinedActionButton(
        icon: FluentIcons.add,
        label: 'Add C++ tools',
        dense: true,
        warning: true,
        onPressed: widget.busy ? null : widget.onAddCppTools,
      );
    }
    return OutlinedActionButton(
      icon: FluentIcons.sync,
      label: 'Update',
      dense: true,
      onPressed: widget.busy ? null : widget.onUpdate,
    );
  }

  void _showMenu(BuildContext context) {
    _menu.showFlyout(
      builder: (flyoutContext) {
        void run(VoidCallback action) {
          Navigator.of(flyoutContext).pop();
          action();
        }

        return MenuFlyout(
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.sync, size: 14),
              text: const Text('Update'),
              onPressed: widget.busy ? null : () => run(widget.onUpdate),
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.repair, size: 14),
              text: const Text('Repair'),
              onPressed: widget.busy ? null : () => run(widget.onRepair),
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.folder_open, size: 14),
              text: const Text('Show in folder'),
              onPressed: () => run(widget.onShowInFolder),
            ),
          ],
        );
      },
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? palette.okSurface : palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Icon(
        sys.FluentIcons.window_dev_tools_24_regular,
        size: 15,
        color: active ? palette.statusOk : palette.textSecondary,
      ),
    );
  }
}
