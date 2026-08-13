import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/flutter_sdk/flutter_upgrade_cubit.dart';
import '../../common/app_loader.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The five upgrade phases as a vertical stepper: a state indicator, the phase
/// label, and the phase's wall clock once it is done.
class UpgradeStepper extends StatelessWidget {
  const UpgradeStepper({super.key, required this.progress});

  final UpgradeProgress progress;

  /// Height of one indicator, and the width the labels align to.
  static const indicatorSize = 18.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final phase in UpgradePhase.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: UpgradePhaseRow(
              phase: phase,
              status: progress.statusOf(phase),
              elapsed: progress.elapsed[phase],
            ),
          ),
      ],
    );
  }
}

/// One phase row. Public so the states can be exercised on their own.
class UpgradePhaseRow extends StatelessWidget {
  const UpgradePhaseRow({
    super.key,
    required this.phase,
    required this.status,
    this.elapsed,
  });

  final UpgradePhase phase;
  final UpgradePhaseStatus status;

  /// Shown once the phase is done. Absent for a phase the output skipped.
  final Duration? elapsed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final styles = AppTextStyles.of(context);
    final showTime = status == UpgradePhaseStatus.done && elapsed != null;

    return Row(
      children: [
        SizedBox(
          width: UpgradeStepper.indicatorSize,
          height: UpgradeStepper.indicatorSize,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: _Indicator(key: ValueKey(status), status: status),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            phase.label,
            style: switch (status) {
              UpgradePhaseStatus.active => styles.rowTitle,
              UpgradePhaseStatus.done =>
                styles.rowLabel.copyWith(color: palette.textSecondary),
              UpgradePhaseStatus.failed =>
                styles.rowTitle.copyWith(color: palette.statusError),
              UpgradePhaseStatus.pending =>
                styles.rowLabel.copyWith(color: palette.textMuted),
            },
          ),
        ),
        if (showTime)
          Text(
            formatPhaseDuration(elapsed!),
            style: styles.caption.copyWith(
              fontFamily: AppTextStyles.monoFamily,
              fontFamilyFallback: AppTextStyles.monoFallback,
            ),
          ),
      ],
    );
  }
}

/// The 18px circle in front of a phase label.
class _Indicator extends StatelessWidget {
  const _Indicator({super.key, required this.status});

  final UpgradePhaseStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return switch (status) {
      // A hollow ring: the phase has not been reached.
      UpgradePhaseStatus.pending => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.borderStrong, width: 1.5),
        ),
      ),
      UpgradePhaseStatus.active => Center(
        child: AppLoader(size: AppLoaderSize.small, color: palette.accent),
      ),
      UpgradePhaseStatus.done => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.okSurface,
        ),
        child: Center(
          child: Icon(
            FluentIcons.check_mark,
            size: 10,
            color: palette.statusOk,
          ),
        ),
      ),
      UpgradePhaseStatus.failed => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.dangerSurface,
        ),
        child: Center(
          child: Icon(
            FluentIcons.chrome_close,
            size: 9,
            color: palette.statusError,
          ),
        ),
      ),
    };
  }
}
