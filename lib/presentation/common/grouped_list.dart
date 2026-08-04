import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A muted, letter-spaced label introducing a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.sectionLabel);
  }
}

/// The quiet container the whole app groups content in: hairline outline,
/// 8px radius, no shadow, no fill.
class GroupedBox extends StatelessWidget {
  const GroupedBox({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        border: Border.all(color: palette.border, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: child,
    );
  }
}

/// A [GroupedBox] whose children are separated by 1px dividers.
///
/// Replaces card grids: one container, dense rows, no shadow.
class GroupedList extends StatelessWidget {
  const GroupedList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GroupedBox(
      child: ClipRRect(
        // Clip so a hovered first/last row doesn't paint over the rounded edge.
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Container(height: AppShape.hairline, color: palette.border),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
