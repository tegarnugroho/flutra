import 'package:fluent_ui/fluent_ui.dart';

import 'app_colors.dart';

/// Typography tokens for the neutral theme.
///
/// Two weights only — [FontWeight.w400] and [FontWeight.w500]. Anything heavier
/// reintroduces the "chunky" look the redesign removes.
class AppTextStyles {
  const AppTextStyles._();

  /// Monospace family for versions, paths and log output.
  ///
  /// `Consolas` ships with Windows and is already used throughout the app (log
  /// views, package tiles); no font asset is bundled. The fallback chain covers
  /// the rare machine without it.
  static const monoFamily = 'Consolas';
  static const monoFallback = <String>['Cascadia Mono', 'Courier New'];

  /// Page heading, e.g. "Dashboard".
  static const pageTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// Small, muted, letter-spaced group label ("Toolchain", "Paths", "Android").
  static const sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    color: AppColors.textMuted,
  );

  /// Primary label inside a list row.
  static const rowTitle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// Inline detail rendered after the row title, behind a ` · ` separator.
  static const rowSecondary = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  /// Left-hand label column of the Paths list.
  static const rowLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Card heading, e.g. "Flutter 3.44.8".
  static const heroTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// Outline pill text (channel badge).
  static const badge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Small trailing/inline note, e.g. "current".
  static const inlineNote = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  /// Mono list value, e.g. a version tag in the versions list.
  static const monoRow = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: AppColors.textTertiary,
  );

  /// [monoRow] for the active entry.
  static const monoRowActive = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: AppColors.textPrimary,
  );

  /// Mono body copy, e.g. changelog commit lines.
  static const monoBody = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    height: 1.7,
    color: AppColors.textSecondary,
  );

  /// A streamed log line.
  static const monoLog = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    height: 1.6,
    color: AppColors.textSecondary,
  );

  /// Text typed into a compact input.
  static const input = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
  );

  /// Right-aligned version numbers.
  static const monoValue = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: AppColors.textSecondary,
  );

  /// Filesystem paths.
  static const monoPath = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: AppColors.textTertiary,
  );

  /// One-line environment status under the page title.
  static const statusLine = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Timestamps and other footnotes.
  static const caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  /// Outlined-button label.
  static const buttonLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
  );

  /// Navigation pane item, unselected.
  static const navItem = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Navigation pane item, selected.
  static const navItemSelected = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// Application name in the title bar.
  static const titleBar = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );
}
