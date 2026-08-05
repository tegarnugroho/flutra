import 'package:fluent_ui/fluent_ui.dart';

/// The single source of truth for every colour in the app.
///
/// The palette is deliberately near-monochrome: greys carry the whole UI and
/// colour is reserved for *status* only ([statusOk] / [statusWarn] /
/// [statusError]). Widgets must never inline a [Color] literal — reference a
/// token here (or [AppPalette] when a themed lookup is wanted).
class AppColors {
  const AppColors._();

  // ---- Surfaces ------------------------------------------------------------

  /// Main content background.
  static const windowBg = Color(0xFF1B1B1D);

  /// Navigation pane + title bar background.
  static const sidebarBg = Color(0xFF161618);

  /// Active nav item and hover states.
  static const surfaceRaised = Color(0xFF26262B);

  /// Terminal surfaces (console, log views). Same value as [sidebarBg] — log
  /// panes read as chrome, not as content.
  static const logBg = Color(0xFF161618);

  // ---- Window caption ------------------------------------------------------

  /// Pressed state of a caption button. One step darker than [surfaceRaised]
  /// (its hover state), the way the Windows caption buttons behave.
  static const captionPressed = Color(0xFF202024);

  /// Hovered close button — the Windows 11 caption red.
  static const captionCloseHover = Color(0xFFC42B1C);

  /// Pressed close button.
  static const captionClosePressed = Color(0xFFB0271A);

  // ---- Borders -------------------------------------------------------------

  /// Hairline dividers and grouped-list outlines.
  static const border = Color(0xFF2A2A2D);

  /// Buttons and emphasised outlines.
  static const borderStrong = Color(0xFF37373C);

  // ---- Text ----------------------------------------------------------------

  /// Titles and primary labels.
  static const textPrimary = Color(0xFFE6E6E9);

  /// Secondary labels, inactive nav items, mono versions.
  static const textSecondary = Color(0xFF9C9CA1);

  /// Mono path text and button labels.
  static const textTertiary = Color(0xFFC9C9CE);

  /// Section labels, captions, disabled text.
  static const textMuted = Color(0xFF6E6E73);

  // ---- Semantic (the ONLY colours in the app) ------------------------------

  /// Healthy / installed.
  static const statusOk = Color(0xFF3FB950);

  /// Missing optional tool, update available.
  static const statusWarn = Color(0xFFD29922);

  /// Missing required tool, failure.
  static const statusError = Color(0xFFF85149);

  // ---- Accent --------------------------------------------------------------

  /// The one accent in the app. Reserved for the selected channel chip on the
  /// Flutter SDK screen — do not spend it anywhere else.
  static const accent = Color(0xFF4B7BEC);

  /// Barely-there tint behind an accent-selected control.
  static const accentBgTint = Color(0xFF22262E);
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

/// The palette as a [ThemeExtension] so widgets can resolve tokens from the
/// active theme instead of importing constants directly.
///
/// Only the dark palette is designed. The app ships a light/dark switcher
/// ([ThemeCubit]), so [light] exists — but see the TODO on it.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.windowBg,
    required this.sidebarBg,
    required this.surfaceRaised,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.statusOk,
    required this.statusWarn,
    required this.statusError,
    required this.accent,
    required this.accentBgTint,
  });

  final Color windowBg;
  final Color sidebarBg;
  final Color surfaceRaised;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textMuted;
  final Color statusOk;
  final Color statusWarn;
  final Color statusError;
  final Color accent;
  final Color accentBgTint;

  static const dark = AppPalette(
    windowBg: AppColors.windowBg,
    sidebarBg: AppColors.sidebarBg,
    surfaceRaised: AppColors.surfaceRaised,
    border: AppColors.border,
    borderStrong: AppColors.borderStrong,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    textMuted: AppColors.textMuted,
    statusOk: AppColors.statusOk,
    statusWarn: AppColors.statusWarn,
    statusError: AppColors.statusError,
    accent: AppColors.accent,
    accentBgTint: AppColors.accentBgTint,
  );

  /// TODO(design): no light palette has been designed for the neutral theme.
  /// The dark values are reused verbatim so the switcher keeps working; the
  /// light surfaces/text ramp must be authored before light mode is shipped.
  static const light = dark;

  /// Resolves the palette from the closest [FluentTheme], falling back to
  /// [dark] (the app's default mode).
  static AppPalette of(BuildContext context) =>
      FluentTheme.of(context).extension<AppPalette>() ?? dark;

  @override
  AppPalette copyWith({
    Color? windowBg,
    Color? sidebarBg,
    Color? surfaceRaised,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textMuted,
    Color? statusOk,
    Color? statusWarn,
    Color? statusError,
    Color? accent,
    Color? accentBgTint,
  }) {
    return AppPalette(
      windowBg: windowBg ?? this.windowBg,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textMuted: textMuted ?? this.textMuted,
      statusOk: statusOk ?? this.statusOk,
      statusWarn: statusWarn ?? this.statusWarn,
      statusError: statusError ?? this.statusError,
      accent: accent ?? this.accent,
      accentBgTint: accentBgTint ?? this.accentBgTint,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      windowBg: c(windowBg, other.windowBg),
      sidebarBg: c(sidebarBg, other.sidebarBg),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textMuted: c(textMuted, other.textMuted),
      statusOk: c(statusOk, other.statusOk),
      statusWarn: c(statusWarn, other.statusWarn),
      statusError: c(statusError, other.statusError),
      accent: c(accent, other.accent),
      accentBgTint: c(accentBgTint, other.accentBgTint),
    );
  }
}
