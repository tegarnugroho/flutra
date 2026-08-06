import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/release_note.dart';
import '../../common/skeleton/skeleton_primitives.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'status_pill.dart';

/// The commits a release brought in, inside an expanded version tile.
///
// TODO: confirm release notes data source (GitHub API vs bundled metadata).
// These are the subjects of the commits between this tag and the previous one,
// read from the local SDK checkout — the same source the old list used. It is
// free and works offline, but it only exists for releases the checkout has
// fetched; the GitHub link covers the rest.
class ReleaseNotesBlock extends StatefulWidget {
  const ReleaseNotesBlock({
    super.key,
    required this.notes,
    required this.loading,
    required this.onOpenChangelog,
    required this.onOpenPullRequest,
  });

  /// How many entries are shown before the footer takes over.
  static const collapsedCount = 8;

  /// Null while [loading]; empty when there is nothing to show.
  final List<ReleaseNote>? notes;
  final bool loading;

  final VoidCallback onOpenChangelog;
  final ValueChanged<int> onOpenPullRequest;

  @override
  State<ReleaseNotesBlock> createState() => _ReleaseNotesBlockState();
}

class _ReleaseNotesBlockState extends State<ReleaseNotesBlock> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final palette = AppPalette.of(context);
    final notes = widget.notes ?? const <ReleaseNote>[];
    final shown = _showAll
        ? notes
        : notes.take(ReleaseNotesBlock.collapsedCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Release notes',
              style: text.rowTitle.copyWith(
                fontSize: 12,
                color: palette.textSecondary,
              ),
            ),
            const Spacer(),
            _Link(label: 'Full changelog ↗', onTap: widget.onOpenChangelog),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.loading)
          const _NotesSkeleton()
        else if (notes.isEmpty)
          Text('Release notes unavailable', style: text.caption)
        else ...[
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _Entry(
              note: shown[i],
              onOpenPullRequest: widget.onOpenPullRequest,
            ),
          ],
          if (!_showAll && notes.length > ReleaseNotesBlock.collapsedCount) ...[
            const SizedBox(height: 10),
            _Link(
              label: 'Show all ${notes.length} commits',
              onTap: () => setState(() => _showAll = true),
            ),
          ],
        ],
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.note, required this.onOpenPullRequest});

  final ReleaseNote note;
  final ValueChanged<int> onOpenPullRequest;

  /// The categories that name a real part of the product rather than
  /// housekeeping — those carry the accent tint.
  static const _accented = {
    ReleaseNoteCategory.engine,
    ReleaseNoteCategory.android,
    ReleaseNoteCategory.ios,
  };

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final palette = AppPalette.of(context);
    final pr = note.pullRequest;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TagPill(
          label: note.category.label,
          accented: _accented.contains(note.category),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                for (final span in note.spans)
                  TextSpan(
                    text: span.text,
                    style: span.isHash
                        ? text.monoValue.copyWith(fontSize: 11.5)
                        : null,
                  ),
              ],
            ),
            style: text.rowSecondary.copyWith(
              fontSize: 12,
              color: palette.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (pr != null) ...[
          const SizedBox(width: 10),
          _PullRequestLink(number: pr, onTap: () => onOpenPullRequest(pr)),
        ],
      ],
    );
  }
}

class _PullRequestLink extends StatefulWidget {
  const _PullRequestLink({required this.number, required this.onTap});

  final int number;
  final VoidCallback onTap;

  @override
  State<_PullRequestLink> createState() => _PullRequestLinkState();
}

class _PullRequestLinkState extends State<_PullRequestLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: 'Open pull request #${widget.number} on GitHub',
          child: Text(
            '#${widget.number}',
            style: AppTextStyles.of(context).monoValue.copyWith(
              fontSize: 11.5,
              color: _hovered ? palette.accent : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet inline link — the same affordance the path rows in Settings use.
class _Link extends StatefulWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: AppTextStyles.of(context).caption.copyWith(
            fontSize: 11.5,
            color: palette.accent,
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: palette.accent,
          ),
        ),
      ),
    );
  }
}

/// Three lines while the git log runs.
class _NotesSkeleton extends StatelessWidget {
  const _NotesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Column(
        children: [
          for (final width in const [320.0, 268.0, 344.0]) ...[
            if (width != 320.0) const SizedBox(height: 8),
            Row(
              children: [
                const SkeletonBox(width: TagPill.width, height: 15),
                const SizedBox(width: 10),
                SkeletonLine(width: width, height: 11),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
