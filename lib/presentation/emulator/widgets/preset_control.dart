import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/emulator/create_emulator_cubit.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Segmented control for the sizing baselines.
///
/// Custom is a readout as much as a choice: it lights up on its own the moment
/// a field is edited, so the label never claims a baseline the numbers no
/// longer match.
class PresetControl extends StatelessWidget {
  const PresetControl({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final EmulatorPreset selected;
  final ValueChanged<EmulatorPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Row(
        children: [
          for (final preset in EmulatorPreset.values)
            Expanded(
              child: _Segment(
                label: preset.label,
                selected: preset == selected,
                // Choosing Custom by hand would mean nothing — it has no
                // baseline to apply, so it is a state, not a button.
                onTap: preset == EmulatorPreset.custom
                    ? null
                    : () => onChanged(preset),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final enabled = widget.onTap != null;

    final Color background;
    if (widget.selected) {
      background = palette.accent;
    } else if (_hovered && enabled) {
      background = palette.surfaceRaised;
    } else {
      background = Colors.transparent;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppShape.radiusControl - 2),
          ),
          child: Text(
            widget.label,
            style: text.buttonLabel.copyWith(
              color: widget.selected
                  ? onAccent(palette)
                  : enabled
                  ? palette.textTertiary
                  : palette.textMuted,
              fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Readable foreground on [AppPalette.accent] — re-exported from the stepper so
/// the whole wizard picks the same tone.
Color onAccent(AppPalette palette) {
  final accent = palette.accent.computeLuminance();
  final dark = palette.brightness == Brightness.dark
      ? const Color(0xFF121214)
      : palette.textPrimary;
  final light = palette.brightness == Brightness.dark
      ? palette.textPrimary
      : const Color(0xFFFFFFFF);
  final onDark = (accent + 0.05) / (dark.computeLuminance() + 0.05);
  final onLight = (light.computeLuminance() + 0.05) / (accent + 0.05);
  return onDark >= onLight ? dark : light;
}
