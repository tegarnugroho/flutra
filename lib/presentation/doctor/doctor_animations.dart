import 'package:fluent_ui/fluent_ui.dart';

/// Every duration and curve the doctor run animation uses, in one place.
class DoctorAnimations {
  const DoctorAnimations._();

  /// Row fade + slide as a check appears.
  static const rowEnter = Duration(milliseconds: 300);
  static const rowEnterCurve = Curves.easeOut;
  static const rowSlide = 4.0;

  /// Status dot pop-in: 0 → 1.35 → 1.0.
  static const dotPop = Duration(milliseconds: 350);
  static const dotPopCurve = Curves.elasticOut;

  /// Pulse ring around the running check.
  static const pulse = Duration(milliseconds: 1500);

  /// Animated "…" on the running row and status line.
  static const ellipsis = Duration(milliseconds: 1200);

  /// Progress bar width changes.
  static const progress = Duration(milliseconds: 300);
  static const progressCurve = Curves.easeOut;

  /// Completion sequence: fill, hold, fade out.
  static const progressHold = Duration(milliseconds: 600);
  static const progressFade = Duration(milliseconds: 300);

  /// Bar thickness.
  static const progressHeight = 3.0;

  /// Whether the user asked for reduced motion. Decorative animation is
  /// skipped; state changes still happen, just instantly.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Zero when motion is reduced, so the same call sites work either way.
  static Duration scale(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
