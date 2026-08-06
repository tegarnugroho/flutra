import 'package:fluent_ui/fluent_ui.dart';

import '../../common/skeleton/skeleton_primitives.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Card heights, shared with the grids that lay them out and with the skeleton
/// that stands in for them, so the three can't drift apart.
const double kStatCardHeight = 88;
const double kQuickActionHeight = 58;

/// The stat labels, which are fixed no matter what the numbers turn out to be.
///
/// Shared with the skeleton so it can print the real words while only the
/// values shimmer — and so renaming one here renames it in both places.
const String kStatDiskUsed = 'Disk used';
const String kStatVirtualDevices = 'Virtual devices';
const String kStatUpdates = 'Updates';
const String kStatDevices = 'Devices';

/// In the order the dashboard lays them out.
const List<String> kDashboardStatLabels = [
  kStatDiskUsed,
  kStatVirtualDevices,
  kStatUpdates,
  kStatDevices,
];

/// The card's frame: padding, border and radius, with nothing in it.
///
/// Shared with the skeleton so the placeholder sits inside the very same box
/// the real card will — the frame is not what the user is waiting for, so it
/// has no reason to be a grey slab first.
class StatCardShell extends StatelessWidget {
  const StatCardShell({super.key, required this.child, this.lifted = false});

  final Widget child;

  /// True while the real card is hovered or focused.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: lifted ? palette.surfaceRaised : Colors.transparent,
        border: Border.all(
          color: lifted ? palette.borderStrong : palette.border,
          width: AppShape.hairline,
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: child,
    );
  }
}

/// One number worth glancing at, with the context that makes it mean
/// something.
class StatCard extends StatefulWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.onTap,
    this.valueColor,
    this.subtitleColor,
  });

  final String label;
  final String value;
  final String subtitle;
  final VoidCallback onTap;
  final Color? valueColor;
  final Color? subtitleColor;

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final lifted = _hovered || _focused;

    return Semantics(
      button: true,
      label: '${widget.label}: ${widget.value}, ${widget.subtitle}',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: StatCardShell(
            lifted: lifted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: text.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.value,
                  style: text.heroTitle.copyWith(
                    fontSize: 16,
                    color: widget.valueColor ?? palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: text.caption.copyWith(color: widget.subtitleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon over a two-line label — the dashboard's shortcuts.
class QuickAction extends StatefulWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  State<QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<QuickAction> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final enabled = widget.onTap != null;
    final lifted = (_hovered || _focused) && enabled;

    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.subtitle}',
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: lifted ? palette.surfaceRaised : Colors.transparent,
              border: Border.all(
                color: lifted ? palette.borderStrong : palette.border,
                width: AppShape.hairline,
              ),
              borderRadius: BorderRadius.circular(AppShape.radiusGroup),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: enabled
                      ? (widget.iconColor ?? palette.textSecondary)
                      : palette.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: text.rowTitle.copyWith(
                          color: enabled
                              ? palette.textPrimary
                              : palette.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: text.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder while the counts are still being gathered.
///
/// The numbers come from avdmanager, adb and sdkmanager — ten seconds of tools,
/// long enough that a row of em dashes would read as an error.
class StatCardsSkeleton extends StatelessWidget {
  const StatCardsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    return SkeletonShimmer(
      child: LayoutBuilder(
        builder: (context, constraints) => GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: constraints.maxWidth < 1000 ? 2 : 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: kStatCardHeight,
          ),
          children: [
            for (final label in kDashboardStatLabels)
              StatCardShell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The label is known before the number is; only the number
                    // and its sub-line are still being fetched.
                    Text(
                      label,
                      style: text.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    const SkeletonLine(width: 58, height: 15),
                    const SizedBox(height: 7),
                    const SkeletonLine(width: 92, height: 10),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
