import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/flutter_sdk/flutter_upgrade_cubit.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'upgrade_stepper.dart';

/// Every string the upgrade dialog shows, kept together rather than scattered
/// through the build methods. The app has no localisation layer yet; when it
/// gains one this class is the single place to route through it.
class UpgradeStrings {
  const UpgradeStrings._();

  static const running = 'Upgrading Flutter';
  static const complete = 'Upgrade complete';
  static const failed = 'Upgrade failed';
  static const cancelled = 'Upgrade cancelled';
  static const cancelledPhase = 'Upgrade stopped before it finished';
  static const startingLog = 'Starting…';
  static const showDetails = 'Show details';
  static const hideDetails = 'Hide details';
  static const cancel = 'Cancel';
  static const done = 'Done';
  static const close = 'Close';
  static const startFailed = 'Failed to start';

  static String channelLine(String channel) => '$channel channel';

  static String ready(String? version) =>
      version == null ? 'Flutter is ready' : 'Flutter $version is ready';

  /// The dialog title for where the upgrade has got to.
  static String titleFor(UpgradeProgress progress) {
    if (progress.isSuccess) return complete;
    if (progress.isFailure) return failed;
    if (progress.cancelled) return cancelled;
    return running;
  }

  /// The line above the bar: the phase, or how the upgrade ended.
  static String phaseLabelFor(UpgradeProgress progress, String? targetVersion) {
    if (progress.isSuccess) return ready(targetVersion);
    if (progress.isFailure) return progress.errorSummary ?? failed;
    if (progress.cancelled) return cancelledPhase;
    return progress.phase.label;
  }
}

/// Icon, title, channel and the version transition, for the dialog's title row.
class UpgradeDialogHeader extends StatelessWidget {
  const UpgradeDialogHeader({
    super.key,
    required this.progress,
    required this.channel,
    required this.currentVersion,
    this.targetVersion,
  });

  final UpgradeProgress progress;
  final String channel;
  final String currentVersion;

  /// Null when the release index could not name the channel tip — the header
  /// then shows the current version alone rather than inventing a target.
  final String? targetVersion;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final styles = AppTextStyles.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(AppShape.radiusGroup),
          ),
          child: Icon(FluentIcons.up, size: 14, color: palette.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                UpgradeStrings.titleFor(progress),
                style: styles.heroTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                UpgradeStrings.channelLine(channel),
                style: styles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: currentVersion),
              if (targetVersion != null) ...[
                const TextSpan(text: ' → '),
                TextSpan(
                  text: targetVersion,
                  style: TextStyle(color: palette.statusOk),
                ),
              ],
            ],
          ),
          style: styles.monoValue,
        ),
      ],
    );
  }
}

/// The dialog's body: phase bar, stepper, and the collapsible details log.
class UpgradeDialogBody extends StatelessWidget {
  const UpgradeDialogBody({
    super.key,
    required this.progress,
    required this.showDetails,
    required this.onToggleDetails,
    this.targetVersion,
  });

  final UpgradeProgress progress;
  final String? targetVersion;

  /// Whether the raw log is expanded. Collapsed by default; a failure opens it.
  final bool showDetails;
  final VoidCallback onToggleDetails;

  Color _barColor(AppPalette palette) {
    if (progress.isFailure) return palette.statusError;
    if (progress.isSuccess) return palette.statusOk;
    return palette.accent;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhaseBar(
            label: UpgradeStrings.phaseLabelFor(progress, targetVersion),
            percent: progress.percent,
            color: _barColor(palette),
          ),
          const SizedBox(height: 18),
          UpgradeStepper(progress: progress),
          const SizedBox(height: 6),
          _DetailsToggle(expanded: showDetails, onPressed: onToggleDetails),
          if (showDetails) ...[
            const SizedBox(height: 6),
            UpgradeDetailsLog(progress: progress),
          ],
        ],
      ),
    );
  }
}

/// Phase label, percentage, and the 4px bar under them.
class _PhaseBar extends StatelessWidget {
  const _PhaseBar({
    required this.label,
    required this.percent,
    required this.color,
  });

  final String label;

  /// 0..1.
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final styles = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: styles.statusLine,
              ),
            ),
            const SizedBox(width: 12),
            Text('${(percent * 100).round()}%', style: styles.monoValue),
          ],
        ),
        const SizedBox(height: 8),
        // The width tween is what makes a phase boundary read as progress
        // rather than a snap — most phases report nothing finer than "done".
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: percent.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              width: double.infinity,
              child: ColoredBox(
                color: palette.surfaceRaised,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: value,
                    heightFactor: 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The "Show details" / "Hide details" affordance.
class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  FluentIcons.chevron_right_med,
                  size: 10,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                expanded
                    ? UpgradeStrings.hideDetails
                    : UpgradeStrings.showDetails,
                style: styles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The recessed box holding the tail of the raw `flutter upgrade` output.
class UpgradeDetailsLog extends StatelessWidget {
  const UpgradeDetailsLog({super.key, required this.progress});

  final UpgradeProgress progress;

  /// Lines kept on screen. The buffer holds far more; this is what fits without
  /// turning the dialog back into a terminal.
  static const visibleLines = 6;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final styles = AppTextStyles.of(context);
    final tail = progress.tail(visibleLines);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.logBg,
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
        border: Border.all(color: palette.border, width: AppShape.hairline),
      ),
      child: tail.isEmpty
          ? Text(UpgradeStrings.startingLog, style: styles.caption)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < tail.length; i++)
                  _FadeInLine(
                    // Keyed by position in the whole stream, so a line already
                    // on screen keeps its element when the window scrolls and
                    // only the genuinely new one fades in.
                    key: ValueKey(progress.tailIndex(visibleLines, i)),
                    child: Text(
                      tail[i].text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.monoLog.copyWith(
                        color: tail[i].isError
                            ? palette.statusError
                            : palette.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Fades its child in once, when it first appears.
class _FadeInLine extends StatelessWidget {
  const _FadeInLine({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}
