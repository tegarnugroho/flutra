import 'package:fluent_ui/fluent_ui.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../application/java/java_cubit.dart';
import '../../../domain/entities/jdk.dart';
import '../../common/app_badge.dart';
import '../../common/outlined_action_button.dart';
import '../../common/status_pill.dart';
import '../../common/tile_box.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// One JDK: what it is, where it came from, and whether builds use it.
class JdkTile extends StatefulWidget {
  const JdkTile({
    super.key,
    required this.jdk,
    required this.isActiveForFlutter,
    required this.task,
    required this.onUseForFlutter,
    required this.onSetJavaHome,
    required this.onShowInFolder,
    required this.onCopyPath,
  });

  final Jdk jdk;

  /// True for the JDK `flutter config --jdk-dir` names.
  final bool isActiveForFlutter;

  /// The work in flight for this JDK, or null when it is idle.
  final JdkTask? task;

  final VoidCallback onUseForFlutter;
  final VoidCallback onSetJavaHome;
  final VoidCallback onShowInFolder;
  final VoidCallback onCopyPath;

  @override
  State<JdkTile> createState() => _JdkTileState();
}

class _JdkTileState extends State<JdkTile> {
  final _menu = FlyoutController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  bool get _busy => widget.task != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final jdk = widget.jdk;
    final usable = jdk.isSelectable;

    return TileBox(
      emphasised: widget.isActiveForFlutter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A JDK path is long and the trailing cluster is fixed-width, so
            // below this the badge and the button label are what give way —
            // the source stays on the mark's tooltip either way.
            final compact = constraints.maxWidth < _compactWidth;
            return Row(
              children: [
                Tooltip(
                  message: 'Found via ${jdk.source.label}',
                  child: _Mark(
                    active: widget.isActiveForFlutter,
                    usable: usable,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _identity(context, palette)),
                const SizedBox(width: 16),
                if (!compact) AppBadge(jdk.source.label),
                if (usable) ...[
                  if (!compact) const SizedBox(width: 10),
                  _useButton(compact: compact),
                  const SizedBox(width: 6),
                  FlyoutTarget(
                    controller: _menu,
                    child: OutlinedActionButton(
                      icon: FluentIcons.more,
                      dense: true,
                      tooltip: 'More actions',
                      onPressed: () => _showMenu(context),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Below this the tile drops its source badge and its button label.
  static const _compactWidth = 620.0;

  /// Nothing to press on an entry that cannot build: the active tile has
  /// nothing to switch to, and an invalid or JRE-only one has nothing to offer.
  Widget _useButton({required bool compact}) {
    final task = widget.task;
    if (task != null) {
      return OutlinedActionButton(
        icon: FluentIcons.switch_widget,
        label: compact ? null : task.label,
        tooltip: compact ? task.label : null,
        dense: true,
        busy: true,
        onPressed: null,
      );
    }
    if (widget.isActiveForFlutter) return const SizedBox.shrink();
    return OutlinedActionButton(
      icon: FluentIcons.switch_widget,
      label: compact ? null : 'Use for Flutter',
      tooltip: 'Use for Flutter',
      dense: true,
      onPressed: widget.onUseForFlutter,
    );
  }

  Widget _identity(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    final jdk = widget.jdk;
    final usable = jdk.isSelectable;
    // A greyed entry stays readable, but never competes with the ones that
    // can actually be chosen.
    final titleColour = usable ? palette.textPrimary : palette.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Every segment gives way before the row does: at a narrow width
            // the name ellipsizes rather than pushing the badge off the tile.
            Flexible(
              child: Text(
                jdk.displayName,
                style: text.rowTitle.copyWith(fontSize: 13, color: titleColour),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (jdk.vendor != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  jdk.vendor!,
                  style: text.inlineNote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (jdk.validity.reason != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  jdk.validity.reason!,
                  style: text.inlineNote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (widget.isActiveForFlutter) ...[
              const SizedBox(width: 8),
              Flexible(
                child: StatusPill(
                  label: 'active',
                  foreground: palette.statusOk,
                  background: palette.okSurface,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        _MetaLine(jdk: jdk),
      ],
    );
  }

  void _showMenu(BuildContext context) {
    _menu.showFlyout(
      builder: (flyoutContext) {
        void run(VoidCallback action) {
          Navigator.of(flyoutContext).pop();
          action();
        }

        return MenuFlyout(
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.set_action, size: 14),
              text: const Text('Set as JAVA_HOME'),
              onPressed: _busy ? null : () => run(widget.onSetJavaHome),
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.folder_open, size: 14),
              text: const Text('Show in folder'),
              onPressed: () => run(widget.onShowInFolder),
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.copy, size: 14),
              text: const Text('Copy path'),
              onPressed: () => run(widget.onCopyPath),
            ),
          ],
        );
      },
    );
  }
}

/// The Java mark in its rounded square, tinted when this JDK is the one in use.
class _Mark extends StatelessWidget {
  const _Mark({required this.active, required this.usable});

  final bool active;
  final bool usable;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? palette.okSurface : palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Icon(
        SimpleIcons.openjdk,
        size: 15,
        color: active
            ? palette.statusOk
            : usable
            ? palette.textSecondary
            : palette.textMuted,
      ),
    );
  }
}

/// `17.0.11 · x86_64 · C:\Program Files\Eclipse Adoptium\jdk-17`.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.jdk});

  final Jdk jdk;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final mono = text.monoMeta.copyWith(fontSize: 11);
    return Row(
      children: [
        if (jdk.version != null) ...[
          Flexible(child: _text(jdk.version!, mono)),
          _Separator(style: text.caption),
        ],
        if (jdk.arch != null) ...[
          Flexible(child: _text(jdk.arch!, mono)),
          _Separator(style: text.caption),
        ],
        // The path is the long one: it gives up its middle first, and the full
        // value stays a hover away.
        Flexible(
          flex: 3,
          child: Tooltip(
            message: jdk.path,
            child: Text(
              jdk.path,
              style: mono,
              maxLines: 1,
              // The tail of a path identifies it; the middle rarely does.
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
            ),
          ),
        ),
      ],
    );
  }

  static Widget _text(String value, TextStyle style) =>
      Text(value, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
}

class _Separator extends StatelessWidget {
  const _Separator({required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('·', style: style),
    );
  }
}
