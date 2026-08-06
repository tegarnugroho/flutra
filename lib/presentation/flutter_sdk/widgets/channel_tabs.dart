import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Segmented text tabs for the release channels.
///
/// Mono, because a channel name sits beside version numbers all the way down
/// the page. The active tab is a surface tint rather than the accent — the
/// accent is spent on the update pill, and two accents on one screen read as
/// two calls to action.
class ChannelTabs extends StatelessWidget {
  const ChannelTabs({
    super.key,
    required this.channels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> channels;
  final String selected;
  final ValueChanged<String> onChanged;

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
          for (final channel in channels)
            _Tab(
              label: channel,
              selected: channel == selected,
              onTap: () => onChanged(channel),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.surfaceRaised
                : _hovered
                ? palette.surfaceRaised.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppShape.radiusControl - 2),
          ),
          child: Text(
            widget.label,
            style: text.monoValue.copyWith(
              fontSize: 12,
              fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w400,
              color: widget.selected
                  ? palette.textPrimary
                  : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
