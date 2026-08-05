import 'package:fluent_ui/fluent_ui.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Trailing marker on a wizard row: either the package is on disk, or it will
/// be fetched when the emulator is created.
class InstallBadge extends StatelessWidget {
  const InstallBadge({super.key, required this.installed, this.size});

  final bool installed;

  /// Approximate download size, when the catalogue knows one.
  ///
  /// `sdkmanager --list` does not report package sizes, so this is null today
  /// and the pill falls back to "Download required".
  // TODO(sizes): wire a real size once the SDK repository can surface one
  // (the XML repository manifests carry it, `--list` does not).
  final String? size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    if (installed) {
      return _Pill(
        border: palette.statusOk,
        child: Text(
          'Installed',
          style: text.badge.copyWith(color: palette.statusOk),
        ),
      );
    }
    return _Pill(
      border: palette.borderStrong,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.download, size: 10, color: palette.textMuted),
          const SizedBox(width: 6),
          Text(size ?? 'Download required', style: text.badge),
        ],
      ),
    );
  }
}

/// A faint "start here if unsure" marker.
class RecommendedTag extends StatelessWidget {
  const RecommendedTag({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return _Pill(
      border: palette.border,
      child: Text(
        'Recommended',
        style: text.badge.copyWith(color: palette.textMuted),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, required this.border});

  final Widget child;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: border, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}

/// The "this will download later" note under a step's list.
class DeferredDownloadBanner extends StatelessWidget {
  const DeferredDownloadBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.accentBgTint,
        border: Border.all(color: palette.accent, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.info, size: 13, color: palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: text.statusLine.copyWith(color: palette.accent),
            ),
          ),
        ],
      ),
    );
  }
}
