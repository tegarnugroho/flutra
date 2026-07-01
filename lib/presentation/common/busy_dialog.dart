import 'package:fluent_ui/fluent_ui.dart';

/// Shows a non-dismissible modal with a spinner while [task] runs, closing it
/// automatically when the task completes (or fails). Use for blocking
/// operations that have no natural streaming progress (e.g. deleting a folder).
Future<void> showBusyDialog(
  BuildContext context, {
  required String title,
  String? message,
  required Future<void> Function() task,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BusyDialog(title: title, message: message, task: task),
  );
}

class _BusyDialog extends StatefulWidget {
  const _BusyDialog({required this.title, this.message, required this.task});

  final String title;
  final String? message;
  final Future<void> Function() task;

  @override
  State<_BusyDialog> createState() => _BusyDialogState();
}

class _BusyDialogState extends State<_BusyDialog> {
  @override
  void initState() {
    super.initState();
    widget.task().whenComplete(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 380),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(
                width: 22, height: 22, child: ProgressRing(strokeWidth: 3)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: FluentTheme.of(context).typography.bodyStrong),
                  if (widget.message != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.message!,
                      style: FluentTheme.of(context).typography.caption?.copyWith(
                            color: FluentTheme.of(context)
                                .resources
                                .textFillColorSecondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
