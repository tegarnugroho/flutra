import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// A selectable row in the wizard's list steps: title, optional subtitle, and
/// slots either side for tags and install badges.
///
/// Same selected treatment as the device cards — accent border, accent tint,
/// check on the right — so the whole wizard reads as one control family.
class WizardOptionRow extends StatefulWidget {
  const WizardOptionRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Sits after the title, e.g. a "Recommended" tag.
  final Widget? leading;

  /// Right-hand slot, e.g. an install badge.
  final Widget? trailing;

  @override
  State<WizardOptionRow> createState() => _WizardOptionRowState();
}

class _WizardOptionRowState extends State<WizardOptionRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final lifted = _hovered || _focused;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.title,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: widget.selected
                  ? palette.accentBgTint
                  : lifted
                  ? palette.surfaceRaised
                  : Colors.transparent,
              border: Border.all(
                color: widget.selected
                    ? palette.accent
                    : lifted
                    ? palette.borderStrong
                    : palette.border,
                width: widget.selected ? 1.5 : AppShape.hairline,
              ),
              borderRadius: BorderRadius.circular(AppShape.radiusGroup),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              style: text.rowTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.leading != null) ...[
                            const SizedBox(width: 8),
                            widget.leading!,
                          ],
                        ],
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: text.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 12),
                  widget.trailing!,
                ],
                if (widget.selected) ...[
                  const SizedBox(width: 10),
                  Icon(
                    FluentIcons.completed_solid,
                    size: 14,
                    color: palette.accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
