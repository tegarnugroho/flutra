import 'package:fluent_ui/fluent_ui.dart';

/// Temporary page for screens that are planned but not yet implemented.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ScaffoldPage(
      header: PageHeader(title: Text(title)),
      content: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.resources.textFillColorTertiary),
            const SizedBox(height: 16),
            Text('$title is coming soon',
                style: theme.typography.subtitle),
            const SizedBox(height: 8),
            Text(
              'This screen is part of the planned build.',
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
