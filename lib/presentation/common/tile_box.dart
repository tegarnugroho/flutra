import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';

/// The bordered tile the version and device lists are built from.
///
/// A list of these replaces the app's grouped rows where each entry is its own
/// object rather than a line in a table: a release you can open, a device you
/// can start. The chrome — hairline border, 10px radius, hover — lives here so
/// the two lists cannot drift apart.
class TileBox extends StatefulWidget {
  const TileBox({
    super.key,
    required this.child,
    this.onTap,
    this.emphasised = false,
    this.outlined = false,
    this.hoverTint = true,
  });

  /// Gap between tiles in a list of them.
  static const gap = 6.0;

  /// Corner radius, two steps up from a grouped list's.
  static const radius = AppShape.radiusGroup + 2;

  final Widget child;
  final VoidCallback? onTap;

  /// Holds the stronger border without a pointer on it — an open tile, or a
  /// device that is running.
  final bool emphasised;

  /// Accent outline, for drawing the eye to a tile that was jumped to.
  final bool outlined;

  /// Whether hovering fills the tile. Off where the fill would run behind
  /// content that is not part of the row itself (an expanded panel).
  final bool hoverTint;

  @override
  State<TileBox> createState() => _TileBoxState();
}

class _TileBoxState extends State<TileBox> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: _hovered && widget.hoverTint
            ? palette.surfaceRaised.withValues(alpha: 0.5)
            : Colors.transparent,
        border: Border.all(
          color: widget.outlined
              ? palette.accent
              : widget.emphasised || _hovered
              ? palette.borderStrong
              : palette.border,
          width: AppShape.hairline,
        ),
        borderRadius: BorderRadius.circular(TileBox.radius),
      ),
      child: widget.child,
    );

    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.onTap == null
          ? tile
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: tile,
            ),
    );
  }
}
