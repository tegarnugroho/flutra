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
    this.titleMeta,
    this.actions = const [],
  });

  final String title;

  /// A muted count beside the title, e.g. `4 devices · 1 running`. For a page
  /// whose subject is a list, where the size of it is worth knowing before
  /// reading it.
  final String? titleMeta;

  /// Right-aligned header actions, usually [OutlinedActionButton]s.
  final List<Widget> actions;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        // stretch, not start: with a loose cross-axis the body sizes to its
        // content's intrinsic width, so a page narrower than the window (the
        // Settings form) put its scrollbar against the content instead of the
        // window edge. Expanded only governs the main axis.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Text(title, style: AppTextStyles.of(context).pageTitle),
                if (titleMeta != null) ...[
                  const SizedBox(width: 10),
                  Padding(
                    // Sits on the title's baseline rather than its centre.
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      titleMeta!,
                      style: AppTextStyles.of(context).caption,
                    ),
                  ),
                ],
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
