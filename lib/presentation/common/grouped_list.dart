import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A muted, letter-spaced label introducing a group of rows.
///
/// [meta] is appended behind a ` · ` separator, e.g. "Versions · 25 available".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.meta});

  final String text;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Text(
      meta == null ? text : '$text · $meta',
      style: AppTextStyles.of(context).sectionLabel,
    );
  }
}

/// The quiet container the whole app groups content in: hairline outline,
/// 8px radius, no shadow, no fill.
class GroupedBox extends StatelessWidget {
  const GroupedBox({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        border: Border.all(color: palette.border, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: child,
    );
  }
}

/// A [GroupedBox] whose children are separated by 1px dividers.
///
/// Replaces card grids and card lists: one container, dense rows, no shadow.
class GroupedList extends StatelessWidget {
  const GroupedList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GroupedBox(
      child: ClipRRect(
        // Clip so a hovered first/last row doesn't paint over the rounded edge.
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Container(height: AppShape.hairline, color: palette.border),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A lazily-built [GroupedList] for long lists.
///
/// Same chrome as [GroupedList] — hairline outline, 8px radius, 1px dividers —
/// but rows are built on demand, so hundreds of entries cost nothing until
/// they scroll into view. Must be given bounded height (an [Expanded] parent).
class GroupedListView extends StatelessWidget {
  const GroupedListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GroupedBox(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
        child: ListView.separated(
          controller: controller,
          padding: EdgeInsets.zero,
          itemCount: itemCount,
          separatorBuilder: (_, _) =>
              Container(height: AppShape.hairline, color: palette.border),
          itemBuilder: (context, index) =>
              itemBuilder(context, index) ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// The standard row inside a [GroupedList].
///
/// Layout: fixed status slot · leading icon · title (+ inline secondary) ·
/// trailing widgets · hover-only actions. Reserving the status slot on every
/// row is what keeps titles aligned whether or not a row has a status.
class GroupedListRow extends StatefulWidget {
  const GroupedListRow({
    super.key,
    this.statusColor,
    this.showStatusSlot = false,
    this.icon,
    this.title,
    this.titleWidget,
    this.secondary,
    this.subtitle,
    this.trailing = const [],
    this.hoverActions = const [],
    this.onTap,
    this.below,
    this.selected = false,
    this.background,
  });

  /// Colour of the leading status dot. Implies [showStatusSlot].
  final Color? statusColor;

  /// Reserve the leading dot slot even when this row has no status.
  final bool showStatusSlot;

  final IconData? icon;

  /// Row title. Ignored when [titleWidget] is given.
  final String? title;
  final Widget? titleWidget;

  /// Inline detail rendered after the title behind a ` · ` separator.
  final String? secondary;

  /// Second line under the title, e.g. a setting description.
  final String? subtitle;

  /// Always-visible trailing widgets.
  final List<Widget> trailing;

  /// Widgets revealed on hover or keyboard focus.
  final List<Widget> hoverActions;

  final VoidCallback? onTap;

  /// Extra content rendered under the row (progress bars, expanded panels).
  final Widget? below;

  final bool selected;

  /// Overrides the row fill (e.g. the accent tint on a running check).
  final Color? background;

  @override
  State<GroupedListRow> createState() => _GroupedListRowState();
}

class _GroupedListRowState extends State<GroupedListRow> {
  bool _hovered = false;
  bool _focused = false;

  bool get _showActions => _hovered || _focused;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final interactive = widget.onTap != null;

    Widget row = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      color:
          widget.background ??
          (widget.selected || _hovered
              ? palette.surfaceRaised
              : Colors.transparent),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.statusColor != null || widget.showStatusSlot) ...[
                _StatusSlot(color: widget.statusColor),
                const SizedBox(width: 10),
              ],
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: palette.textSecondary),
                const SizedBox(width: 10),
              ],
              Expanded(child: _title()),
              for (final t in widget.trailing) ...[
                const SizedBox(width: 10),
                t,
              ],
              if (widget.hoverActions.isNotEmpty && _showActions)
                for (final a in widget.hoverActions) ...[
                  const SizedBox(width: 8),
                  a,
                ],
            ],
          ),
          if (widget.below != null) widget.below!,
        ],
      ),
    );

    if (widget.onTap != null) {
      row = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: row,
      );
    }

    return FocusableActionDetector(
      mouseCursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      descendantsAreFocusable: true,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        if (widget.onTap != null)
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap!();
              return null;
            },
          ),
      },
      child: row,
    );
  }

  Widget _title() {
    if (widget.titleWidget != null) return widget.titleWidget!;
    final title = Text.rich(
      TextSpan(
        text: widget.title ?? '',
        style: AppTextStyles.of(context).rowTitle,
        children: [
          if (widget.secondary != null)
            TextSpan(
              text: ' · ${widget.secondary}',
              style: AppTextStyles.of(context).rowSecondary,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (widget.subtitle == null) return title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 2),
        Text(widget.subtitle!, style: AppTextStyles.of(context).caption),
      ],
    );
  }
}

class _StatusSlot extends StatelessWidget {
  const _StatusSlot({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 6,
      height: 6,
      child: color == null
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
    );
  }
}
