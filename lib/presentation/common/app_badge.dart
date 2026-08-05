import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A quiet outline pill for short metadata (channel, API level, ABI…).
///
/// No fill and no per-value colour — badges label, they don't signal.
class AppBadge extends StatelessWidget {
  const AppBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: palette.borderStrong,
          width: AppShape.hairline,
        ),
      ),
      child: Text(text, style: AppTextStyles.of(context).badge),
    );
  }
}
