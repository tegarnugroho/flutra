import 'package:fluent_ui/fluent_ui.dart';

import 'app_colors.dart';

/// Typography tokens for the neutral theme.
///
/// Two weights only — [FontWeight.w400] and [FontWeight.w500]. Anything heavier
/// reintroduces the "chunky" look the redesign removes.
///
/// The styles are resolved against an [AppPalette] rather than being constants:
/// every one of them carries a text tone, and those tones flip between light
/// and dark. Read them with `AppTextStyles.of(context)`.
@immutable
class AppTextStyles {
  const AppTextStyles.fromPalette(this._palette);

  /// Resolves the styles from the closest [FluentTheme].
  factory AppTextStyles.of(BuildContext context) =>
      AppTextStyles.fromPalette(AppPalette.of(context));

  final AppPalette _palette;

  /// Monospace family for versions, paths and log output.
  ///
  /// `Consolas` ships with Windows and is already used throughout the app (log
  /// views, package tiles); no font asset is bundled. The fallback chain covers
  /// the rare machine without it.
  static const monoFamily = 'Consolas';
  static const monoFallback = <String>['Cascadia Mono', 'Courier New'];

  /// Page heading, e.g. "Dashboard".
  TextStyle get pageTitle => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: _palette.textPrimary,
  );

  /// Small, muted, letter-spaced group label ("Toolchain", "Paths", "Android").
  TextStyle get sectionLabel => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    color: _palette.textMuted,
  );

  /// Primary label inside a list row.
  TextStyle get rowTitle => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: _palette.textPrimary,
  );

  /// Inline detail rendered after the row title, behind a ` · ` separator.
  TextStyle get rowSecondary => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    color: _palette.textMuted,
  );

  /// Left-hand label column of the Paths list.
  TextStyle get rowLabel => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: _palette.textSecondary,
  );

  /// Card heading, e.g. "Flutter 3.44.8".
  TextStyle get heroTitle => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: _palette.textPrimary,
  );

  /// The one number a screen exists to report — the active SDK version on the
  /// Flutter SDK panel. Mono, because it is a version and versions are read
  /// digit by digit.
  TextStyle get heroVersion => TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: _palette.textPrimary,
  );

  /// Mono metadata sitting under a heading: Dart version, revision, path.
  TextStyle get monoMeta => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: _palette.textMuted,
  );

  /// Outline pill text (channel badge).
  TextStyle get badge => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: _palette.textSecondary,
  );

  /// Small trailing/inline note, e.g. "current".
  TextStyle get inlineNote => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: _palette.textMuted,
  );

  /// Mono list value, e.g. a version tag in the versions list.
  TextStyle get monoRow => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: _palette.textTertiary,
  );

  /// [monoRow] for the active entry.
  TextStyle get monoRowActive => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: _palette.textPrimary,
  );

  /// Mono body copy, e.g. changelog commit lines.
  TextStyle get monoBody => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    height: 1.7,
    color: _palette.textSecondary,
  );

  /// A streamed log line.
  TextStyle get monoLog => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    height: 1.6,
    color: _palette.textSecondary,
  );

  /// Text typed into a compact input.
  TextStyle get input => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: _palette.textTertiary,
  );

  /// Right-aligned version numbers.
  TextStyle get monoValue => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: _palette.textSecondary,
  );

  /// Filesystem paths.
  TextStyle get monoPath => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: _palette.textTertiary,
  );

  /// One-line environment status under the page title.
  TextStyle get statusLine => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: _palette.textSecondary,
  );

  /// Timestamps and other footnotes.
  TextStyle get caption => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: _palette.textMuted,
  );

  /// Outlined-button label.
  TextStyle get buttonLabel => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: _palette.textTertiary,
  );

  /// Navigation pane item, unselected.
  TextStyle get navItem => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: _palette.textSecondary,
  );

  /// Navigation pane item, selected.
  TextStyle get navItemSelected => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: _palette.textPrimary,
  );

  /// Application name in the title bar.
  TextStyle get titleBar => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: _palette.textPrimary,
  );
}
