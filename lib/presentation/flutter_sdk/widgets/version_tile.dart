import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/flutter_release.dart';
import '../../../domain/entities/release_note.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'release_notes_block.dart';
import 'status_pill.dart';

/// One release, as a tile that opens into its release notes.
///
/// Collapsed it is two lines and a chevron; the Switch button only appears once
/// the tile is open, so a list of forty releases is forty version numbers
/// rather than forty buttons.
class VersionTile extends StatefulWidget {
  const VersionTile({
    super.key,
    required this.release,
    required this.isCurrent,
    required this.expanded,
    required this.highlighted,
    required this.dartBadge,
    required this.notes,
    required this.notesLoading,
    required this.onToggle,
    required this.onSwitch,
    required this.onOpenGitHub,
    required this.onOpenPullRequest,
  });

  final FlutterRelease release;

  /// The release the local SDK is actually on.
  final bool isCurrent;

  final bool expanded;

  /// Briefly outlined in accent after "update available" jumps to it.
  final bool highlighted;

  /// This release's Dart version, set only when it is a different minor than
  /// the release above it in the list — the boundary worth calling out.
  final String? dartBadge;

  /// The release's commits, or null while they are being read.
  ///
  /// Owned by the page rather than by this tile: the list disposes a tile as
  /// soon as it scrolls out of view, and a cache living here would take the
  /// git log with it — scrolling away and back would run it again.
  final List<ReleaseNote>? notes;
  final bool notesLoading;

  final VoidCallback onToggle;
  final VoidCallback onSwitch;
  final VoidCallback onOpenGitHub;
  final ValueChanged<int> onOpenPullRequest;

  @override
  State<VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<VersionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final open = widget.expanded;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hovered && !open
                ? palette.surfaceRaised.withValues(alpha: 0.5)
                : Colors.transparent,
            border: Border.all(
              color: widget.highlighted
                  ? palette.accent
                  : open || _hovered
                  ? palette.borderStrong
                  : palette.border,
              width: AppShape.hairline,
            ),
            borderRadius: BorderRadius.circular(AppShape.radiusGroup + 2),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, palette),
                if (open) ...[
                  Container(
                    height: AppShape.hairline,
                    color: palette.border,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _dotSlot + _dotGap + 12,
                      12,
                      12,
                      14,
                    ),
                    child: ReleaseNotesBlock(
                      key: ValueKey(widget.release.hash),
                      notes: widget.notes,
                      loading: widget.notesLoading,
                      onOpenChangelog: widget.onOpenGitHub,
                      onOpenPullRequest: widget.onOpenPullRequest,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Width of the status dot, reserved on every tile so version numbers line
  /// up whether or not a tile is the current one.
  static const _dotSlot = 8.0;
  static const _dotGap = 10.0;

  Widget _header(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    return Container(
      color: widget.expanded
          ? palette.surfaceRaised.withValues(alpha: 0.4)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: _dotSlot,
            height: _dotSlot,
            child: widget.isCurrent
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.statusOk,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: _dotGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titleLine(text, palette),
                const SizedBox(height: 3),
                Text(_meta(), style: text.caption),
              ],
            ),
          ),
          if (widget.expanded && !widget.isCurrent) ...[
            const SizedBox(width: 12),
            OutlinedActionButton(
              icon: FluentIcons.switch_widget,
              label: 'Switch',
              dense: true,
              onPressed: widget.onSwitch,
            ),
          ],
          const SizedBox(width: 10),
          AnimatedRotation(
            turns: widget.expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Icon(
              FluentIcons.chevron_down,
              size: 12,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleLine(AppTextStyles text, AppPalette palette) {
    return Row(
      children: [
        Flexible(
          child: Text(
            widget.release.displayVersion,
            style: text.monoRow.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: widget.isCurrent
                  ? palette.textPrimary
                  : palette.textTertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.isCurrent) ...[
          const SizedBox(width: 8),
          Text('installed · in use', style: text.inlineNote),
        ],
        if (widget.dartBadge != null) ...[
          const SizedBox(width: 8),
          StatusPill(
            label: 'Dart ${widget.dartBadge}',
            foreground: palette.statusWarn,
            background: palette.warnSurface,
            mono: true,
          ),
        ],
      ],
    );
  }

  /// `Dart 3.12.0 · Aug 6, 2026 · 214 commits · 2 weeks ago`.
  String _meta() {
    final release = widget.release;
    final notes = widget.notes;
    final parts = <String>[
      if (release.displayDartVersion != null)
        'Dart ${release.displayDartVersion}',
      if (release.releaseDate != null) formatReleaseDate(release.releaseDate!),
      // TODO: commit count requires releases metadata — the index publishes
      // none, so this only appears once the tile has been opened and the git
      // log behind the release notes has run.
      if (notes != null && notes.isNotEmpty) '${notes.length} commits',
      if (widget.isCurrent && release.releaseDate != null)
        relativeAge(release.releaseDate!, DateTime.now()),
    ];
    return parts.join(' · ');
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Aug 6, 2026`.
String formatReleaseDate(DateTime date) {
  final local = date.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

/// `2 weeks ago` — how long the SDK in use has been out.
///
/// Coarse on purpose: the exact date is already on the same line, so this only
/// has to answer "recent or old".
String relativeAge(DateTime date, DateTime now) {
  final days = now.difference(date).inDays;
  if (days < 1) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'a week ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  if (days < 365) return '${days ~/ 30} months ago';
  final years = days ~/ 365;
  return years == 1 ? 'a year ago' : '$years years ago';
}

/// The Dart minor a release bundles, e.g. `3.12` from `3.12.2`.
String? dartMinor(FlutterRelease release) {
  final version = release.displayDartVersion;
  if (version == null) return null;
  final parts = version.split('.');
  return parts.length < 2 ? version : '${parts[0]}.${parts[1]}';
}
