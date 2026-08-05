import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../common/compact_field.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// How a size in MB is written out.
enum SizeUnit { megabytes, gigabytes }

/// A labelled size picker: preset choices plus `Custom…`, which swaps the
/// dropdown for an inline numeric field of the same width.
///
/// Everything is stored in MB regardless of how it is displayed — the AVD
/// config format is unchanged by this UI.
class SizeDropdown extends StatefulWidget {
  const SizeDropdown({
    super.key,
    required this.label,
    required this.valueMb,
    required this.options,
    required this.unit,
    required this.onChanged,
    this.minMb = 0,
    this.maxMb,
    this.hint,
    this.zeroLabel,
  });

  final String label;
  final int valueMb;

  /// Offered values, in MB.
  final List<int> options;

  final SizeUnit unit;
  final ValueChanged<int> onChanged;

  final int minMb;

  /// Upper bound for custom entry, when one is known.
  final int? maxMb;

  /// Muted note under the field, e.g. "Host: 16 GB".
  final String? hint;

  /// What 0 is called, e.g. "None" for an SD card.
  final String? zeroLabel;

  @override
  State<SizeDropdown> createState() => _SizeDropdownState();
}

/// Sentinel for the "Custom…" entry — no real size is negative.
const int _customSentinel = -1;

class _SizeDropdownState extends State<SizeDropdown> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      // Blur commits, matching the dropdown's "choose and move on" feel.
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    _controller.text = '${widget.valueMb}';
    setState(() {
      _editing = true;
      _error = null;
    });
    _focus.requestFocus();
  }

  void _commit() {
    final raw = _controller.text.trim();
    final value = int.tryParse(raw);
    if (value == null) {
      setState(() => _error = 'Whole numbers only');
      return;
    }
    if (value < widget.minMb) {
      setState(() => _error = 'Minimum ${widget.minMb} MB');
      return;
    }
    final max = widget.maxMb;
    if (max != null && value > max) {
      setState(() => _error = 'Maximum $max MB');
      return;
    }
    setState(() {
      _editing = false;
      _error = null;
    });
    widget.onChanged(value);
  }

  void _revert() {
    setState(() {
      _editing = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    // A value the presets don't offer is already custom — show it as such
    // rather than snapping the dropdown to a number the user never picked.
    final offList = !widget.options.contains(widget.valueMb);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: text.rowLabel),
        const SizedBox(height: 6),
        if (_editing || offList)
          _CustomInput(
            controller: _controller,
            focus: _focus,
            onCommit: _commit,
            onRevert: _revert,
            onDone: _editing ? null : _startEditing,
            editing: _editing,
            display: _format(widget.valueMb),
          )
        else
          CompactCombo<int>(
            value: widget.valueMb,
            items: [
              for (final mb in widget.options)
                CompactComboItem(value: mb, label: _format(mb)),
              const CompactComboItem(value: _customSentinel, label: 'Custom…'),
            ],
            onChanged: (v) =>
                v == _customSentinel ? _startEditing() : widget.onChanged(v),
          ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            style: text.caption.copyWith(color: palette.statusError),
          ),
        ] else if (widget.hint != null) ...[
          const SizedBox(height: 4),
          Text(widget.hint!, style: text.caption),
        ],
      ],
    );
  }

  String _format(int mb) {
    if (mb == 0 && widget.zeroLabel != null) return widget.zeroLabel!;
    if (widget.unit == SizeUnit.megabytes) return '$mb MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb % 1 == 0 ? 0 : 1)} GB';
  }
}

/// The inline numeric editor a `Custom…` choice swaps in.
class _CustomInput extends StatelessWidget {
  const _CustomInput({
    required this.controller,
    required this.focus,
    required this.onCommit,
    required this.onRevert,
    required this.onDone,
    required this.editing,
    required this.display,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onCommit;
  final VoidCallback onRevert;

  /// Re-enters editing when the field is showing a committed custom value.
  final VoidCallback? onDone;

  final bool editing;
  final String display;

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      return GestureDetector(
        onTap: onDone,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AbsorbPointer(
            child: CompactCombo<String>(
              value: display,
              items: [CompactComboItem(value: display, label: display)],
              onChanged: (_) {},
            ),
          ),
        ),
      );
    }
    return CallbackShortcuts(
      // Esc abandons the edit; the dropdown's previous value stands.
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onRevert},
      child: CompactField(
        controller: controller,
        focusNode: focus,
        icon: null,
        placeholder: 'MB',
        onSubmitted: (_) => onCommit(),
      ),
    );
  }
}

/// CPU core picker, capped at the host's count with a warning past the
/// comfortable range.
class CoreDropdown extends StatelessWidget {
  const CoreDropdown({
    super.key,
    required this.cores,
    required this.hostCores,
    required this.onChanged,
  });

  final int cores;

  /// Null when the host count could not be read — the list then falls back to a
  /// conservative range and no hint is shown.
  final int? hostCores;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final max = hostCores ?? 8;
    // Leaving fewer than two cores to the host makes the whole machine crawl.
    final crowded = hostCores != null && cores > hostCores! - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('CPU cores', style: text.rowLabel),
            if (crowded) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Leaves little for the host OS',
                child: Icon(
                  FluentIcons.warning,
                  size: 11,
                  color: palette.statusWarn,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        CompactCombo<int>(
          value: cores,
          items: [
            for (var i = 1; i <= max; i++)
              CompactComboItem(value: i, label: '$i'),
          ],
          onChanged: onChanged,
        ),
        if (hostCores != null) ...[
          const SizedBox(height: 4),
          Text('Host: $hostCores cores', style: text.caption),
        ],
      ],
    );
  }
}
