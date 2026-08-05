import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shows a confirmation dialog. Returns true if confirmed.
///
/// The single confirmation used across the app: cancel is a plain outlined
/// button, and a [destructive] confirm is filled in [AppColors.statusError].
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: Text(title, style: AppTextStyles.of(context).heroTitle),
      content: Text(message, style: AppTextStyles.of(context).statusLine),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          style: destructive
              ? ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                    AppColors.statusError,
                  ),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Prompts for a single text value (e.g. a new AVD name). Returns null on cancel.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  String confirmLabel = 'OK',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => ContentDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: Text(title, style: AppTextStyles.of(context).heroTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          InfoLabel(
            label: label,
            child: TextBox(
              controller: controller,
              autofocus: true,
              maxLines: 1,
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ),
        ],
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(
          child: Text(confirmLabel),
          onPressed: () => Navigator.pop(context, controller.text),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
