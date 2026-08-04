import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_text_styles.dart';

/// Standard padding for scrollable page bodies, matching the header gutter.
const kPageBodyPadding = EdgeInsets.fromLTRB(20, 14, 20, 24);

/// The frame every page shares: title row with right-aligned actions, then the
/// page body filling the rest of the window.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;

  /// Right-aligned header actions, usually [OutlinedActionButton]s.
  final List<Widget> actions;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Text(title, style: AppTextStyles.pageTitle),
                const Spacer(),
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions[i],
                ],
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
