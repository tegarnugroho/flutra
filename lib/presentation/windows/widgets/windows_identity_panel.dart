import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as sys;

import '../../../domain/entities/windows_toolchain.dart';
import '../../common/outlined_action_button.dart';
import '../../common/status_pill.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Whether a Windows desktop build can run, and the one thing to do about it.
class WindowsIdentityPanel extends StatelessWidget {
  const WindowsIdentityPanel({
    super.key,
    required this.toolchain,
    required this.busy,
    required this.onInstall,
    required this.onFixIssues,
  });

  final WindowsToolchain toolchain;
  final bool busy;

  /// Runs the Build Tools bootstrapper — the nothing-installed case.
  final VoidCallback onInstall;

  /// Scrolls to the first unmet requirement.
  final VoidCallback onFixIssues;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised.withValues(alpha: 0.35),
        border: Border.all(
          color: palette.borderStrong,
          width: AppShape.hairline,
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Mark(palette: palette, ready: toolchain.isReady),
          const SizedBox(width: 14),
          Expanded(child: _identity(context, palette)),
          const SizedBox(width: 16),
          _action(context),
        ],
      ),
    );
  }

  Widget _identity(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    final unmet = toolchain.unmet;

    final String headline;
    if (toolchain.nothingInstalled) {
      headline = 'Build tools not installed';
    } else if (unmet.isEmpty) {
      headline = 'Windows toolchain ready';
    } else {
      headline =
          '${unmet.length} issue${unmet.length == 1 ? '' : 's'} blocking '
          'Windows builds';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                headline,
                style: text.heroTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: StatusPill(
                label: toolchain.isReady ? 'ready' : 'action needed',
                foreground: toolchain.isReady
                    ? palette.statusOk
                    : palette.statusWarn,
                background: toolchain.isReady
                    ? palette.okSurface
                    : palette.warnSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (toolchain.nothingInstalled)
          Text(
            'Windows desktop builds need the MSVC compiler and a Windows SDK. '
            'Build Tools installs both without the Visual Studio IDE.',
            style: text.caption,
          )
        else
          Text(
            toolchain.summary,
            style: text.monoMeta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _action(BuildContext context) {
    final text = AppTextStyles.of(context);
    final palette = AppPalette.of(context);

    if (toolchain.isReady) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.check_mark, size: 12, color: palette.textMuted),
          const SizedBox(width: 6),
          Text('Windows builds can run', style: text.caption),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        OutlinedActionButton(
          icon: toolchain.nothingInstalled
              ? FluentIcons.download
              : FluentIcons.repair,
          label: toolchain.nothingInstalled
              ? 'Install Build Tools'
              : 'Fix issues',
          warning: true,
          busy: busy,
          onPressed: busy
              ? null
              : (toolchain.nothingInstalled ? onInstall : onFixIssues),
        ),
        const SizedBox(height: 5),
        // The thing that most often reads as the app hanging.
        Text('Windows will ask for permission', style: text.caption),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.palette, required this.ready});

  final AppPalette palette;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ready ? palette.okSurface : palette.accentBgTint,
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: Icon(
        sys.FluentIcons.window_dev_tools_24_regular,
        size: 20,
        color: ready ? palette.statusOk : palette.accent,
      ),
    );
  }
}
