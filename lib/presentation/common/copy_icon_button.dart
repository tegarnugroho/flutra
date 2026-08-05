import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Copies [value] to the clipboard and confirms via the app's usual info bar.
///
/// [label] names what was copied, both in the tooltip and the confirmation.
class CopyIconButton extends StatefulWidget {
  const CopyIconButton({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  State<CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<CopyIconButton> {
  bool _hovered = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    await displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text('${widget.label} copied'),
          content: Text(widget.value),
          severity: InfoBarSeverity.info,
          isLong: true,
          onClose: close,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: 'Copy ${widget.label.toLowerCase()}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              FluentIcons.copy,
              size: 13,
              color: _hovered ? palette.textPrimary : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
