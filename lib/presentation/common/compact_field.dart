import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Standard height for compact inputs so filters and dropdowns line up.
const kCompactFieldHeight = 30.0;

/// The shared decoration for compact inputs.
BoxDecoration compactFieldDecoration(AppPalette palette) => BoxDecoration(
      borderRadius: BorderRadius.circular(AppShape.radiusControl),
      border: Border.all(color: palette.border, width: AppShape.hairline),
    );

/// A small single-line input used for filters and searches.
class CompactField extends StatelessWidget {
  const CompactField({
    super.key,
    required this.placeholder,
    this.onChanged,
    this.controller,
    this.icon = FluentIcons.search,
    this.width,
  });

  final String placeholder;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  /// Leading icon; pass null for a plain field.
  final IconData? icon;

  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: width,
      height: kCompactFieldHeight,
      child: TextBox(
        controller: controller,
        placeholder: placeholder,
        style: AppTextStyles.input,
        placeholderStyle:
            AppTextStyles.input.copyWith(color: palette.textMuted),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        prefix: icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(icon, size: 12, color: palette.textMuted),
              ),
        decoration: WidgetStateProperty.all(compactFieldDecoration(palette)),
        onChanged: onChanged,
      ),
    );
  }
}

/// One choice in a [CompactCombo].
class CompactComboItem<T> {
  const CompactComboItem({required this.value, required this.label});

  final T value;
  final String label;
}

/// A dropdown styled to match [CompactField].
///
/// Hand-rolled rather than a themed [ComboBox]: fluent's combo box exposes no
/// decoration hook, so it can't be made to match the app's hairline geometry.
class CompactCombo<T> extends StatefulWidget {
  const CompactCombo({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.placeholder = 'Select',
    this.width,
  });

  final T? value;
  final List<CompactComboItem<T>> items;
  final ValueChanged<T> onChanged;
  final String placeholder;
  final double? width;

  @override
  State<CompactCombo<T>> createState() => _CompactComboState<T>();
}

class _CompactComboState<T> extends State<CompactCombo<T>> {
  final _flyout = FlyoutController();
  bool _hovered = false;

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  void _open() {
    if (widget.items.isEmpty) return;
    _flyout.showFlyout(
      builder: (flyoutContext) => MenuFlyout(
        items: [
          for (final item in widget.items)
            MenuFlyoutItem(
              text: Text(item.label, style: AppTextStyles.input),
              selected: item.value == widget.value,
              onPressed: () {
                Navigator.of(flyoutContext).pop();
                widget.onChanged(item.value);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final selected = widget.items
        .where((i) => i.value == widget.value)
        .map((i) => i.label)
        .firstOrNull;
    return FlyoutTarget(
      controller: _flyout,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _open,
          child: Container(
            width: widget.width,
            height: kCompactFieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: compactFieldDecoration(palette).copyWith(
              color: _hovered ? palette.surfaceRaised : null,
            ),
            child: Row(
              mainAxisSize:
                  widget.width == null ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Flexible(
                  child: Text(
                    selected ?? widget.placeholder,
                    style: selected == null
                        ? AppTextStyles.input
                            .copyWith(color: palette.textMuted)
                        : AppTextStyles.input,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(FluentIcons.chevron_down,
                    size: 10, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A checkbox drawn to the app's geometry: hairline box, accent when checked.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!checked),
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: checked ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: checked ? palette.accent : palette.borderStrong,
              width: AppShape.hairline,
            ),
          ),
          child: checked
              ? Icon(FluentIcons.check_mark,
                  size: 10, color: palette.textPrimary)
              : null,
        ),
      ),
    );
  }
}

/// An on/off switch: accent track when on, hairline track when off.
class AppToggle extends StatelessWidget {
  const AppToggle({super.key, required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!checked),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: checked ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: checked ? palette.accent : palette.borderStrong,
              width: AppShape.hairline,
            ),
          ),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: checked ? palette.textPrimary : palette.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small on/off chip used for list filters ("Updates", "Installed").
class ToggleChip extends StatelessWidget {
  const ToggleChip({
    super.key,
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!checked),
        child: Container(
          height: kCompactFieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: checked ? palette.accentBgTint : Colors.transparent,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
            border: Border.all(
              color: checked ? palette.accent : palette.border,
              width: AppShape.hairline,
            ),
          ),
          // widthFactor keeps the chip hugging its label — a Container with an
          // alignment would expand to the whole row.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: checked ? AppTextStyles.rowTitle : AppTextStyles.navItem,
            ),
          ),
        ),
      ),
    );
  }
}
