import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// A tinted pill: fill and label share one semantic hue, no border.
///
/// Distinct from [AppBadge], which is a neutral outline that only labels —
/// this one signals, so it is spent on state (`latest`, `update available`)
/// and on the category tags in the release notes.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.onTap,
    this.mono = false,
  });

  final String label;
  final Color foreground;
  final Color background;

  /// Makes the pill an affordance. Hover lifts the fill.
  final VoidCallback? onTap;

  final bool mono;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final style = (mono ? text.monoMeta : text.badge).copyWith(
      fontSize: 10.5,
      color: foreground,
    );

    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: style),
    );

    if (onTap == null) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}

/// A category tag in the release notes: fixed width, so the messages beside
/// them line up into a column instead of stepping in and out.
class TagPill extends StatelessWidget {
  const TagPill({
    super.key,
    required this.label,
    required this.accented,
  });

  /// Wide enough for "android", the longest category.
  static const width = 58.0;

  final String label;

  /// Accent tint for the tags that name a platform or the engine; neutral fill
  /// for the housekeeping ones.
  final bool accented;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accented ? palette.accentBgTint : palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Text(
        label,
        style: AppTextStyles.of(context).badge.copyWith(
          fontSize: 10,
          color: accented ? palette.accent : palette.textMuted,
        ),
      ),
    );
  }
}
