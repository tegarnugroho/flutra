import 'package:fluent_ui/fluent_ui.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Central Fluent UI theme definitions.
///
/// The app runs a professional neutral (near-monochrome) theme: the accent is a
/// grey ramp so no chrome is tinted, and colour only ever appears through the
/// semantic status tokens in [AppPalette].
///
/// Both modes are built by the same function over their [AppPalette], so a
/// token wired into one ramp cannot be forgotten in the other.
class AppTheme {
  const AppTheme._();

  /// Neutral accent ramp. Fluent uses [FluentThemeData.accentColor] for filled
  /// buttons, progress rings, checkboxes and selection — a grey ramp keeps all
  /// of those monochrome without having to restyle each control.
  ///
  /// The ramp ends at the palette's text tones, so it inverts with the theme
  /// along with everything else.
  static AccentColor _neutralAccent(AppPalette palette) {
    final isDark = palette.brightness == Brightness.dark;
    return AccentColor.swatch({
      'darkest': isDark ? const Color(0xFF3A3A41) : const Color(0xFFB8B8BE),
      'darker': isDark ? const Color(0xFF4A4A52) : const Color(0xFFA0A0A7),
      'dark': isDark ? const Color(0xFF5C5C64) : const Color(0xFF87878E),
      'normal': palette.textSecondary,
      'light': isDark ? const Color(0xFFB0B0B5) : const Color(0xFF44444A),
      'lighter': palette.textTertiary,
      'lightest': palette.textPrimary,
    });
  }

  /// Kept for callers that referenced the accent swatch directly.
  static AccentColor get accentColor => _neutralAccent(AppPalette.dark);

  static FluentThemeData light() => _build(AppPalette.light);

  static FluentThemeData dark() => _build(AppPalette.dark);

  static FluentThemeData _build(AppPalette palette) {
    final text = AppTextStyles.fromPalette(palette);
    return FluentThemeData(
      brightness: palette.brightness,
      accentColor: _neutralAccent(palette),
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: palette.windowBg,
      micaBackgroundColor: palette.windowBg,
      acrylicBackgroundColor: palette.windowBg,
      cardColor: palette.windowBg,
      menuColor: palette.sidebarBg,
      shadowColor: const Color(0x00000000), // no drop shadows anywhere
      extensions: [palette],
      dividerTheme: DividerThemeData(
        thickness: AppShape.hairline,
        decoration: BoxDecoration(color: palette.border),
      ),
      navigationPaneTheme: _paneTheme(palette, text),
    );
  }

  /// Sidebar styling: flat [AppPalette.sidebarBg] surface, raised tile for the
  /// active item, muted labels for everything else.
  static NavigationPaneThemeData _paneTheme(
    AppPalette palette,
    AppTextStyles text,
  ) {
    return NavigationPaneThemeData(
      backgroundColor: palette.sidebarBg,
      overlayBackgroundColor: palette.sidebarBg,
      highlightColor: palette.borderStrong,
      itemHeaderTextStyle: text.sectionLabel,
      headerPadding: const EdgeInsetsDirectional.only(top: 12, bottom: 2),
      tileColor: WidgetStateProperty.resolveWith((states) {
        if (states.isPressed || states.isHovered) {
          return palette.surfaceRaised;
        }
        return Colors.transparent;
      }),
      selectedTextStyle: WidgetStateProperty.all(text.navItemSelected),
      unselectedTextStyle: WidgetStateProperty.all(text.navItem),
      selectedIconColor: WidgetStateProperty.all(palette.textPrimary),
      unselectedIconColor: WidgetStateProperty.all(palette.textSecondary),
    );
  }
}
