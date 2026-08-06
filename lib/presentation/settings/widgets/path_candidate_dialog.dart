import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Lists the SDK installs a disk scan found and returns the one picked, or null
/// when the user backs out.
///
/// Picking sets an override rather than changing what auto-detection reports:
/// the user chose *this* install out of several, and that choice has to survive
/// the next launch.
Future<String?> showPathCandidateDialog(
  BuildContext context, {
  required String label,
  required List<String> candidates,
  String? current,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      final text = AppTextStyles.of(context);
      return ContentDialog(
        constraints: const BoxConstraints(maxWidth: 560),
        title: Text(
          candidates.isEmpty
              ? 'No $label found'
              : 'Found ${candidates.length} $label '
                  'install${candidates.length == 1 ? '' : 's'}',
        ),
        content: candidates.isEmpty
            ? Text(
                'Nothing that looks like a $label turned up on the drives '
                'this app can read. Use Change to point at it directly.',
                style: text.caption,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pick the one to use.', style: text.caption),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final path in candidates)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _CandidateTile(
                                path: path,
                                isCurrent: path == current,
                                onPick: () =>
                                    Navigator.of(context).pop(path),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(candidates.isEmpty ? 'Close' : 'Cancel'),
          ),
        ],
      );
    },
  );
}

class _CandidateTile extends StatefulWidget {
  const _CandidateTile({
    required this.path,
    required this.isCurrent,
    required this.onPick,
  });

  final String path;
  final bool isCurrent;
  final VoidCallback onPick;

  @override
  State<_CandidateTile> createState() => _CandidateTileState();
}

class _CandidateTileState extends State<_CandidateTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPick,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? palette.accentBgTint : palette.sidebarBg,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
            border: Border.all(
              color: widget.isCurrent ? palette.accent : palette.border,
              width: AppShape.hairline,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.path,
                  style: text.monoPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                ),
              ),
              if (widget.isCurrent) ...[
                const SizedBox(width: 8),
                Text('in use', style: text.inlineNote),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
