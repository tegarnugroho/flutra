import 'package:fluent_ui/fluent_ui.dart';

/// A selectable card tile used throughout the create-emulator wizard.
class SelectTile extends StatelessWidget {
  const SelectTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : theme.resources.cardBackgroundFillColorDefault,
          border: Border.all(
            color: selected
                ? accent
                : theme.resources.controlStrokeColorDefault,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: selected
                    ? accent
                    : theme.resources.textFillColorSecondary,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.typography.body),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(FluentIcons.completed_solid, size: 16, color: accent),
          ],
        ),
      ),
    );
  }
}
