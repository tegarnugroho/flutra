import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'outlined_action_button.dart';

/// The shared centred message used for empty, error and pre-run states.
///
/// Deliberately plain: a monochrome icon, a headline, one caption line and a
/// single outlined action. No illustrations, no coloured circles.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon = FluentIcons.refresh,
    this.onAction,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  /// Tints the icon with [AppColors.statusError] instead of a muted grey.
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 24,
                color: isError ? palette.statusError : palette.textSecondary),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center, style: AppTextStyles.heroTitle),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center, style: AppTextStyles.caption),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              OutlinedActionButton(
                icon: actionIcon,
                label: actionLabel,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
