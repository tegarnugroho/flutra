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
    this.secondaryActionLabel,
    this.secondaryActionIcon = FluentIcons.folder_open,
    this.onSecondaryAction,
    this.footer,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  /// A second way out of this state, beside [actionLabel].
  ///
  /// The empty state that needed this is "no Android SDK": installing one and
  /// pointing at one you already have are equally reasonable answers, and
  /// picking one of them to hide behind a menu would be picking wrong for half
  /// the people who land here.
  final String? secondaryActionLabel;
  final IconData secondaryActionIcon;
  final VoidCallback? onSecondaryAction;

  /// Anything that belongs under the actions — progress, an expandable detail
  /// pane. Kept as a slot so this widget stays a layout and does not grow a
  /// second job.
  final Widget? footer;

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
            Icon(
              icon,
              size: 24,
              color: isError ? palette.statusError : palette.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.of(context).heroTitle,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.of(context).caption,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedActionButton(
                    icon: actionIcon,
                    label: actionLabel,
                    onPressed: onAction,
                  ),
                  if (secondaryActionLabel != null &&
                      onSecondaryAction != null)
                    OutlinedActionButton(
                      icon: secondaryActionIcon,
                      label: secondaryActionLabel,
                      onPressed: onSecondaryAction,
                    ),
                ],
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: 16),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
