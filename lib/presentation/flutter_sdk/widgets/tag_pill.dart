import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// A category tag in the release notes: fixed width, so the messages beside
/// them line up into a column instead of stepping in and out.
class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.label, required this.accented});

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
