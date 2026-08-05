import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// One choice in a [SegmentedControl].
class Segment<T> {
  const Segment({required this.value, required this.label, this.enabled = true});

  final T value;
  final String label;

  /// A segment that reports state but can't be chosen — e.g. "Custom", which
  /// only ever becomes true as a consequence of editing something else.
  final bool enabled;
}

/// A row of mutually exclusive choices, for three or four short options where a
/// dropdown would hide the alternatives behind a click.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<Segment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

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
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments)
            _Segment(
              label: segment.label,
              selected: segment.value == selected,
              onTap: segment.enabled ? () => onChanged(segment.value) : null,
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
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 14),
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

/// Readable foreground for text sitting on [AppPalette.accent].
///
/// The accent is the lighter tone in dark mode and the darker one in light, so
/// the label has to pick whichever of the palette's extremes actually contrasts
/// rather than assuming one of them.
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
