import 'package:fluent_ui/fluent_ui.dart';

/// The single source of truth for every colour in the app.
///
/// The palette is deliberately near-monochrome: greys carry the whole UI and
/// colour is reserved for *status* only ([AppPalette.statusOk] /
/// [AppPalette.statusWarn] / [AppPalette.statusError]).
///
/// Widgets must never inline a [Color] literal, and must resolve tones through
/// [AppPalette] rather than the raw constants below — the constants are one
/// theme's values, [AppPalette] is what flips between light and dark.
class AppColors {
  const AppColors._();

  // ---- Dark surfaces -------------------------------------------------------

  /// Main content background.
  static const windowBg = Color(0xFF1B1B1D);

  /// Navigation pane + title bar background.
  static const sidebarBg = Color(0xFF161618);

  /// Active nav item and hover states.
  static const surfaceRaised = Color(0xFF26262B);

  /// Terminal surfaces (console, log views). Same value as [sidebarBg] — log
  /// panes read as chrome, not as content.
  static const logBg = Color(0xFF161618);

  // ---- Dark borders --------------------------------------------------------

  /// Hairline dividers and grouped-list outlines.
  static const border = Color(0xFF2A2A2D);

  /// Buttons and emphasised outlines.
  static const borderStrong = Color(0xFF37373C);

  // ---- Dark text -----------------------------------------------------------

  /// Titles and primary labels.
  static const textPrimary = Color(0xFFE6E6E9);

  /// Secondary labels, inactive nav items, mono versions.
  static const textSecondary = Color(0xFF9C9CA1);

  /// Mono path text and button labels.
  static const textTertiary = Color(0xFFC9C9CE);

  /// Section labels, captions, disabled text.
  static const textMuted = Color(0xFF6E6E73);

  // ---- Dark semantic -------------------------------------------------------

  /// Healthy / installed.
  static const statusOk = Color(0xFF3FB950);

  /// Missing optional tool, update available.
  static const statusWarn = Color(0xFFD29922);

  /// Missing required tool, failure.
  static const statusError = Color(0xFFF85149);

  /// Fill behind a destructive control — the error hue at low strength, so the
  /// button reads as dangerous without shouting.
  static const dangerSurface = Color(0xFF2A1719);

  /// The one accent in the app. Reserved for the selected channel chip on the
  /// Flutter SDK screen — do not spend it anywhere else.
  static const accent = Color(0xFF4B7BEC);

  /// Barely-there tint behind an accent-selected control.
  static const accentBgTint = Color(0xFF22262E);

  /// Pressed state of a caption button, one step past the hover surface.
  static const captionPressed = Color(0xFF202024);

  // ---- Light surfaces ------------------------------------------------------
  //
  // The light ramp mirrors the dark one's *relationships* rather than its
  // values: chrome sits a shade off the content surface, and the four text
  // tones keep their prominence order (primary → tertiary → secondary → muted).

  /// Main content background.
  static const windowBgLight = Color(0xFFFFFFFF);

  /// Navigation pane + title bar background. Slightly grey so the chrome band
  /// still separates from the content the way it does in dark mode.
  static const sidebarBgLight = Color(0xFFF3F3F3);

  /// Active nav item and hover states — black at ~7% over [sidebarBgLight].
  static const surfaceRaisedLight = Color(0xFFE6E6E8);

  /// Terminal surfaces. Same value as [sidebarBgLight], as in dark mode.
  static const logBgLight = Color(0xFFF3F3F3);

  // ---- Light borders -------------------------------------------------------

  static const borderLight = Color(0xFFE3E3E6);
  static const borderStrongLight = Color(0xFFCACACF);

  // ---- Light text ----------------------------------------------------------

  /// Titles and primary labels. 16.9:1 on white.
  static const textPrimaryLight = Color(0xFF1A1A1D);

  /// Secondary labels, inactive nav items, mono versions. 6.5:1 on white.
  static const textSecondaryLight = Color(0xFF5C5C63);

  /// Mono path text and button labels. 11.4:1 on white.
  static const textTertiaryLight = Color(0xFF35353B);

  /// Section labels, captions, disabled text.
  ///
  /// 3.5:1 on white — under AA for body copy, which is the point: this tone is
  /// only ever used for text that is deliberately subordinate (captions,
  /// timestamps, disabled labels), never for a heading or a value.
  static const textMutedLight = Color(0xFF8A8A90);

  // ---- Light semantic ------------------------------------------------------
  //
  // Darkened from the dark-mode hues so they stay legible on white.

  static const statusOkLight = Color(0xFF1A7F37);
  static const statusWarnLight = Color(0xFF8A6100);
  static const statusErrorLight = Color(0xFFC8232C);
  static const dangerSurfaceLight = Color(0xFFFDECEC);
  static const accentLight = Color(0xFF2F5FD1);
  static const accentBgTintLight = Color(0xFFEDF2FD);

  /// Pressed state of a caption button — black at ~10% over [sidebarBgLight].
  static const captionPressedLight = Color(0xFFDBDBDD);

  // ---- Theme-independent ---------------------------------------------------

  /// Hovered close button — the Windows 11 caption red.
  ///
  /// One of the two colours that do *not* flip with the theme: Windows draws
  /// the same red close button in both, and users read it as a system control.
  static const captionCloseHover = Color(0xFFC42B1C);

  /// Pressed close button.
  static const captionClosePressed = Color(0xFFB0271A);

  // ---- Loading placeholders ------------------------------------------------

  /// Skeleton fill and shimmer highlight, resolved by [Brightness] because they
  /// are alpha values composited over whatever surface they land on rather than
  /// palette tones.
  static const _skeletonBaseDark = Color(0x0DFFFFFF); // white @ 5%
  static const _skeletonBaseLight = Color(0x0D000000); // black @ 5%
  static const _skeletonHighlightDark = Color(0x17FFFFFF); // white @ 9%
  static const _skeletonHighlightLight = Color(0x08000000); // black @ 3%

  /// Resting colour of a skeleton placeholder.
  static Color skeletonBase(Brightness brightness) =>
      brightness == Brightness.dark ? _skeletonBaseDark : _skeletonBaseLight;

  /// The brighter band swept across a skeleton. On light surfaces this is
  /// *less* dark than the base, so the sweep never reads as glare.
  static Color skeletonHighlight(Brightness brightness) =>
      brightness == Brightness.dark
      ? _skeletonHighlightDark
      : _skeletonHighlightLight;
}

/// Shared geometry so radii and hairlines stay consistent.
class AppShape {
  const AppShape._();

  /// Controls and nav items.
  static const radiusControl = 6.0;

  /// Grouped list containers.
  static const radiusGroup = 8.0;

  /// Custom-drawn window frame.
  static const radiusWindow = 10.0;

  /// Hairline width. 1 rather than 0.5 — sub-pixel borders render unevenly
  /// across the fractional device pixel ratios Windows reports.
  static const hairline = 1.0;
}

/// The palette as a [ThemeExtension], so every widget resolves its colours from
/// the active theme and light/dark flips with no widget-level branching.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.windowBg,
    required this.sidebarBg,
    required this.surfaceRaised,
    required this.logBg,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.statusOk,
    required this.statusWarn,
    required this.statusError,
    required this.dangerSurface,
    required this.accent,
    required this.accentBgTint,
    required this.captionPressed,
  });

  /// Which ramp this is. Widgets that composite alpha (skeletons, shadows)
  /// need to know which direction "lighter" points.
  final Brightness brightness;

  final Color windowBg;
  final Color sidebarBg;
  final Color surfaceRaised;
  final Color logBg;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textMuted;
  final Color statusOk;
  final Color statusWarn;
  final Color statusError;

  /// Fill behind destructive controls. The border and label stay
  /// [statusError] — this is only the wash behind them.
  final Color dangerSurface;

  final Color accent;
  final Color accentBgTint;
  final Color captionPressed;

  /// Hover fill of a caption button — the same surface nav items hover to.
  Color get captionHover => surfaceRaised;

  /// Hovered close button. Red in both themes, per Windows convention.
  Color get captionCloseHover => AppColors.captionCloseHover;

  /// Pressed close button.
  Color get captionClosePressed => AppColors.captionClosePressed;

  /// Icon colour on the hovered close button. White on that red in both
  /// themes — the one place the app draws pure white text.
  Color get captionCloseForeground => const Color(0xFFFFFFFF);

  static const dark = AppPalette(
    brightness: Brightness.dark,
    windowBg: AppColors.windowBg,
    sidebarBg: AppColors.sidebarBg,
    surfaceRaised: AppColors.surfaceRaised,
    logBg: AppColors.logBg,
    border: AppColors.border,
    borderStrong: AppColors.borderStrong,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    textMuted: AppColors.textMuted,
    statusOk: AppColors.statusOk,
    statusWarn: AppColors.statusWarn,
    statusError: AppColors.statusError,
    dangerSurface: AppColors.dangerSurface,
    accent: AppColors.accent,
    accentBgTint: AppColors.accentBgTint,
    captionPressed: AppColors.captionPressed,
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    windowBg: AppColors.windowBgLight,
    sidebarBg: AppColors.sidebarBgLight,
    surfaceRaised: AppColors.surfaceRaisedLight,
    logBg: AppColors.logBgLight,
    border: AppColors.borderLight,
    borderStrong: AppColors.borderStrongLight,
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    textTertiary: AppColors.textTertiaryLight,
    textMuted: AppColors.textMutedLight,
    statusOk: AppColors.statusOkLight,
    statusWarn: AppColors.statusWarnLight,
    statusError: AppColors.statusErrorLight,
    dangerSurface: AppColors.dangerSurfaceLight,
    accent: AppColors.accentLight,
    accentBgTint: AppColors.accentBgTintLight,
    captionPressed: AppColors.captionPressedLight,
  );

  /// Resolves the palette from the closest [FluentTheme], falling back to
  /// [dark] (the app's default mode).
  static AppPalette of(BuildContext context) =>
      FluentTheme.of(context).extension<AppPalette>() ?? dark;

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? windowBg,
    Color? sidebarBg,
    Color? surfaceRaised,
    Color? logBg,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textMuted,
    Color? statusOk,
    Color? statusWarn,
    Color? statusError,
    Color? dangerSurface,
    Color? accent,
    Color? accentBgTint,
    Color? captionPressed,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      windowBg: windowBg ?? this.windowBg,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      logBg: logBg ?? this.logBg,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textMuted: textMuted ?? this.textMuted,
      statusOk: statusOk ?? this.statusOk,
      statusWarn: statusWarn ?? this.statusWarn,
      statusError: statusError ?? this.statusError,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      accent: accent ?? this.accent,
      accentBgTint: accentBgTint ?? this.accentBgTint,
      captionPressed: captionPressed ?? this.captionPressed,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      // Brightness is a mode, not a ramp: snap it at the halfway point so
      // alpha-compositing widgets never see an in-between value.
      brightness: t < 0.5 ? brightness : other.brightness,
      windowBg: c(windowBg, other.windowBg),
      sidebarBg: c(sidebarBg, other.sidebarBg),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      logBg: c(logBg, other.logBg),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textMuted: c(textMuted, other.textMuted),
      statusOk: c(statusOk, other.statusOk),
      statusWarn: c(statusWarn, other.statusWarn),
      statusError: c(statusError, other.statusError),
      dangerSurface: c(dangerSurface, other.dangerSurface),
      accent: c(accent, other.accent),
      accentBgTint: c(accentBgTint, other.accentBgTint),
      captionPressed: c(captionPressed, other.captionPressed),
    );
  }
}
