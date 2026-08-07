import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/windows_toolchain.dart';
import '../../common/outlined_action_button.dart';
import '../../common/tile_box.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// One requirement: whether it is met, what was detected, and the one thing
/// that would fix it.
///
/// A satisfied requirement carries no button. The page is a checklist, and a
/// row of buttons next to green checks turns it back into a control panel.
class RequirementTile extends StatelessWidget {
  const RequirementTile({
    super.key,
    required this.requirement,
    required this.busy,
    required this.pending,
    required this.onAction,
    this.trailingPath,
  });

  final WindowsRequirement requirement;

  /// True while any operation runs — every action disables.
  final bool busy;

  /// True while this requirement's own short action runs.
  final bool pending;

  final VoidCallback onAction;

  /// An install path to show under the detail line, ellipsized from the left
  /// with the whole value on hover.
  final String? trailingPath;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    final ok = requirement.satisfied;

    return TileBox(
      emphasised: !ok,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                ok ? FluentIcons.check_mark : FluentIcons.warning,
                size: 14,
                color: ok ? palette.statusOk : palette.statusWarn,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    requirement.kind.label,
                    style: text.rowTitle.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    requirement.detail,
                    style: text.monoMeta.copyWith(fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (trailingPath != null) ...[
                    const SizedBox(height: 2),
                    Tooltip(
                      message: trailingPath!,
                      child: Text(
                        trailingPath!,
                        style: text.monoMeta.copyWith(
                          fontSize: 11,
                          color: palette.textMuted,
                        ),
                        maxLines: 1,
                        // The tail of a path identifies it; the middle does not.
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ],
                  if (requirement.caption != null) ...[
                    const SizedBox(height: 4),
                    Text(requirement.caption!, style: text.caption),
                  ],
                ],
              ),
            ),
            if (requirement.action.label != null) ...[
              const SizedBox(width: 14),
              OutlinedActionButton(
                icon: _icon(requirement.action),
                label: pending ? 'Working…' : requirement.action.label,
                dense: true,
                warning: true,
                busy: pending,
                onPressed: busy ? null : onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _icon(WindowsRequirementAction action) => switch (action) {
    WindowsRequirementAction.installBuildTools ||
    WindowsRequirementAction.addWindowsSdk => FluentIcons.download,
    WindowsRequirementAction.addCppWorkload => FluentIcons.add,
    WindowsRequirementAction.repair => FluentIcons.repair,
    WindowsRequirementAction.openDeveloperSettings => FluentIcons.settings,
    WindowsRequirementAction.enableWindowsDesktop => FluentIcons.check_mark,
    WindowsRequirementAction.none => FluentIcons.info,
  };
}
