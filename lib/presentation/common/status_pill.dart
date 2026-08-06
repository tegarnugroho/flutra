import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_text_styles.dart';

/// A tinted pill: fill and label share one semantic hue, no border.
///
/// Distinct from [AppBadge], which is a neutral outline that only labels —
/// this one signals, so it is spent on state (`running`, `update available`)
/// and never on plain metadata.
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

  /// Makes the pill an affordance.
  final VoidCallback? onTap;

  final bool mono;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final style = (mono ? text.monoMeta : text.badge).copyWith(
      fontSize: 10.5,
      color: foreground,
    );

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      // A pill never wraps: in a tight row it gives up its tail rather than
      // growing a second line and pushing the row's height around.
      child: Text(
        label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (onTap == null) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}
