import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Copies [value] to the clipboard and confirms in place: the icon becomes a
/// check for a moment.
///
/// In place rather than through an info bar — the confirmation belongs next to
/// what was copied, and a banner for a clipboard write is too loud.
///
/// [label] names what was copied, in the tooltip.
class CopyIconButton extends StatefulWidget {
  const CopyIconButton({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  State<CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<CopyIconButton> {
  /// How long the check stays up before the icon returns.
  static const _feedback = Duration(milliseconds: 1200);

  bool _hovered = false;
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(_feedback, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: _copied ? 'Copied' : 'Copy ${widget.label.toLowerCase()}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              _copied ? FluentIcons.check_mark : FluentIcons.copy,
              size: 13,
              color: _copied
                  ? palette.statusOk
                  : _hovered
                  ? palette.textPrimary
                  : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
