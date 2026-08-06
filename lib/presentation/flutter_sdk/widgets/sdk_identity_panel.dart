import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/flutter_sdk/flutter_sdk_cubit.dart';
import '../../../domain/entities/flutter_sdk_info.dart';
import '../../common/app_badge.dart';
import '../../common/copy_icon_button.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'flutter_glyph.dart';
import 'status_pill.dart';

/// The panel that answers "which Flutter am I on, and can my shell find it".
///
/// The one highlighted surface on the page: a stronger border and a faint fill,
/// so the version reads as the page's subject and the version list below it as
/// the choices.
class SdkIdentityPanel extends StatelessWidget {
  const SdkIdentityPanel({
    super.key,
    required this.info,
    required this.updateAvailable,
    required this.latestKnown,
    required this.latestVersion,
    required this.pathStatus,
    required this.onAddToPath,
    required this.onRevealLatest,
  });

  /// Revisions are 40-char hashes; this is what git itself shows.
  static const _shortRevisionLength = 8;

  final FlutterSdkInfo info;

  /// True when the channel has published something newer than HEAD.
  final bool updateAvailable;

  /// Whether the comparison could be made at all. False for a checkout with no
  /// HEAD to compare, or a channel whose index entry is missing — "latest" is
  /// then a claim the app cannot support, so it says the channel and stops.
  final bool latestKnown;

  /// The newest version on the channel, for the update pill's tooltip.
  final String? latestVersion;

  final SdkPathStatus pathStatus;

  /// Null when there is no SDK path to add.
  final VoidCallback? onAddToPath;

  /// Scrolls the version list to the newest release and opens it.
  final VoidCallback onRevealLatest;

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
          _Mark(palette: palette),
          const SizedBox(width: 14),
          Expanded(child: _identity(context, palette)),
          const SizedBox(width: 16),
          _PathStatus(status: pathStatus, onAddToPath: onAddToPath),
        ],
      ),
    );
  }

  Widget _identity(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    final revision = info.frameworkRevision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                info.version,
                style: text.heroVersion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            if (updateAvailable)
              Tooltip(
                message: latestVersion == null
                    ? 'Show the newest release on this channel'
                    : 'Show Flutter $latestVersion in the list below',
                child: StatusPill(
                  label: 'update available',
                  foreground: palette.accent,
                  background: palette.accentBgTint,
                  onTap: onRevealLatest,
                ),
              )
            else if (latestKnown)
              StatusPill(
                label: '${info.channel} · latest',
                foreground: palette.statusOk,
                background: palette.okSurface,
              )
            else
              AppBadge(info.channel),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _separated(context, [
            // The channel is only in the pill while the SDK is up to date, and
            // it is the first thing to check when it is not.
            if (updateAvailable) _meta(context, value: info.channel),
            if (info.dartVersion != null)
              _meta(context, value: 'Dart ${info.dartVersion}'),
            if (revision != null)
              _meta(
                context,
                value: revision.length > _shortRevisionLength
                    ? revision.substring(0, _shortRevisionLength)
                    : revision,
                copyValue: revision,
                copyLabel: 'Revision',
              ),
            if (info.sdkPath != null)
              _meta(
                context,
                value: info.sdkPath!,
                copyValue: info.sdkPath!,
                copyLabel: 'SDK path',
              ),
          ]),
        ),
      ],
    );
  }

  /// Interleaves the fragments with a middle dot. Part of the [Wrap]'s run, so
  /// a separator wraps with the fragment it belongs to rather than dangling.
  List<Widget> _separated(BuildContext context, List<Widget> fragments) {
    final style = AppTextStyles.of(context).monoMeta;
    return [
      for (var i = 0; i < fragments.length; i++) ...[
        if (i > 0) Text('·', style: style),
        fragments[i],
      ],
    ];
  }

  /// One metadata fragment: mono value, optional copy action.
  Widget _meta(
    BuildContext context, {
    required String value,
    String? copyValue,
    String? copyLabel,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            value,
            style: AppTextStyles.of(context).monoMeta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (copyValue != null) ...[
          const SizedBox(width: 4),
          CopyIconButton(value: copyValue, label: copyLabel ?? 'Value'),
        ],
      ],
    );
  }
}

/// The logo in its rounded square.
class _Mark extends StatelessWidget {
  const _Mark({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.accentBgTint,
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: FlutterGlyph(color: palette.accent, size: 20),
    );
  }
}

/// Whether a terminal can find this SDK, and the way out when it cannot.
class _PathStatus extends StatelessWidget {
  const _PathStatus({required this.status, required this.onAddToPath});

  final SdkPathStatus status;
  final VoidCallback? onAddToPath;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);

    // Unknown says nothing: offering to fix PATH off a failed read would be
    // worse than staying quiet.
    if (status == SdkPathStatus.unknown) return const SizedBox.shrink();

    if (status == SdkPathStatus.present) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.check_mark, size: 12, color: palette.textMuted),
          const SizedBox(width: 6),
          Text('In system PATH', style: text.caption),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        OutlinedActionButton(
          icon: FluentIcons.warning,
          label: 'Add to PATH',
          warning: true,
          tooltip: 'Add Flutter to PATH so "flutter" works in any terminal',
          onPressed: onAddToPath,
        ),
        const SizedBox(height: 5),
        Text('Not detected in system PATH', style: text.caption),
      ],
    );
  }
}
