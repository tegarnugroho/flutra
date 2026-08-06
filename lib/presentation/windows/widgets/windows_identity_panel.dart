import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as sys;

import '../../../domain/entities/windows_toolchain.dart';
import '../../common/copy_icon_button.dart';
import '../../common/outlined_action_button.dart';
import '../../common/status_pill.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// What a Windows desktop build would use, and what is stopping it.
class WindowsIdentityPanel extends StatelessWidget {
  const WindowsIdentityPanel({
    super.key,
    required this.toolchain,
    required this.busy,
    required this.onInstall,
    required this.onFix,
  });

  final WindowsToolchain toolchain;
  final bool busy;

  /// Installs Build Tools from nothing.
  final VoidCallback onInstall;

  /// Adds the C++ workload, or repairs — whichever the status calls for. Null
  /// when there is nothing to fix.
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final status = toolchain.status;
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
          Expanded(child: _identity(context, palette, status)),
          const SizedBox(width: 16),
          _action(context, status),
        ],
      ),
    );
  }

  Widget _identity(
    BuildContext context,
    AppPalette palette,
    WindowsToolchainStatus status,
  ) {
    final text = AppTextStyles.of(context);
    final active = toolchain.active;
    final sdk = toolchain.newestSdk;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                status.headline,
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
        if (status.detail != null)
          Text(status.detail!, style: text.caption)
        else if (active != null)
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _meta(context, '${active.displayName} ${active.majorMinor}'),
              Text('·', style: text.monoMeta),
              if (sdk != null) ...[
                _meta(context, 'Windows SDK ${sdk.displayVersion}'),
                Text('·', style: text.monoMeta),
              ],
              _meta(context, active.installPath, copy: true),
            ],
          ),
      ],
    );
  }

  Widget _meta(BuildContext context, String value, {bool copy = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(
            value,
            style: AppTextStyles.of(context).monoMeta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (copy) ...[
          const SizedBox(width: 4),
          CopyIconButton(value: value, label: 'Install path'),
        ],
      ],
    );
  }

  Widget _action(BuildContext context, WindowsToolchainStatus status) {
    final text = AppTextStyles.of(context);
    if (toolchain.isReady) {
      final palette = AppPalette.of(context);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.check_mark, size: 12, color: palette.textMuted),
          const SizedBox(width: 6),
          Text('Windows builds can run', style: text.caption),
        ],
      );
    }

    final missing = status == WindowsToolchainStatus.missingVisualStudio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        OutlinedActionButton(
          icon: FluentIcons.download,
          label: missing ? 'Install Build Tools' : 'Fix toolchain',
          warning: true,
          busy: busy,
          tooltip: missing
              ? 'Downloads the official installer and runs it'
              : 'Adds the missing C++ tools through the Visual Studio Installer',
          onPressed: busy ? null : (missing ? onInstall : onFix),
        ),
        const SizedBox(height: 5),
        // The one thing that surprises people: this app cannot do it silently.
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
