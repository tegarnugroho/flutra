import 'package:fluent_ui/fluent_ui.dart';

/// Shows a destructive-action confirmation dialog. Returns true if confirmed.
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
      title: Text(title),
      content: Text(message),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          style: destructive
              ? ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                    const Color(0xFFC42B1C),
                  ),
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
      title: Text(title),
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
