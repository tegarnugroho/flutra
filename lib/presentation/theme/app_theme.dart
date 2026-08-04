import 'package:fluent_ui/fluent_ui.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Central Fluent UI theme definitions.
///
/// The app runs a professional neutral (near-monochrome) theme: the accent is a
/// grey ramp so no chrome is tinted, and colour only ever appears through the
/// semantic status tokens in [AppColors].
class AppTheme {
  const AppTheme._();

  /// Neutral accent ramp. Fluent uses [FluentThemeData.accentColor] for filled
  /// buttons, progress rings, checkboxes and selection — a grey ramp keeps all
  /// of those monochrome without having to restyle each control.
  static AccentColor get _neutralAccent => AccentColor.swatch({
        'darkest': const Color(0xFF3A3A41),
        'darker': const Color(0xFF4A4A52),
        'dark': const Color(0xFF5C5C64),
        'normal': AppColors.textSecondary,
        'light': const Color(0xFFB0B0B5),
        'lighter': AppColors.textTertiary,
        'lightest': AppColors.textPrimary,
      });

  /// Kept for backwards compatibility with callers that referenced the old
  /// green swatch.
  static AccentColor get accentColor => _neutralAccent;

  /// TODO(design): light mode still uses the dark palette's tokens (see
  /// [AppPalette.light]). A light surface/text ramp has to be authored before
  /// the light theme is presentable.
  static FluentThemeData light() => FluentThemeData(
        brightness: Brightness.light,
        accentColor: _neutralAccent,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),
        cardColor: Colors.white,
        extensions: const [AppPalette.light],
      );

  static FluentThemeData dark() => FluentThemeData(
        brightness: Brightness.dark,
        accentColor: _neutralAccent,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: AppColors.windowBg,
        micaBackgroundColor: AppColors.windowBg,
        acrylicBackgroundColor: AppColors.windowBg,
        cardColor: AppColors.windowBg,
        menuColor: AppColors.sidebarBg,
        shadowColor: const Color(0x00000000), // no drop shadows anywhere
        extensions: const [AppPalette.dark],
        dividerTheme: const DividerThemeData(
          thickness: AppShape.hairline,
          decoration: BoxDecoration(color: AppColors.border),
        ),
        navigationPaneTheme: _paneTheme,
      );

  /// Sidebar styling: flat [AppColors.sidebarBg] surface, raised tile for the
  /// active item, muted labels for everything else.
  static NavigationPaneThemeData get _paneTheme => NavigationPaneThemeData(
        backgroundColor: AppColors.sidebarBg,
        overlayBackgroundColor: AppColors.sidebarBg,
        highlightColor: AppColors.borderStrong,
        itemHeaderTextStyle: AppTextStyles.sectionLabel,
        headerPadding: const EdgeInsetsDirectional.only(top: 12, bottom: 2),
        tileColor: WidgetStateProperty.resolveWith((states) {
          if (states.isPressed || states.isHovered) {
            return AppColors.surfaceRaised;
          }
          return Colors.transparent;
        }),
        selectedTextStyle:
            WidgetStateProperty.all(AppTextStyles.navItemSelected),
        unselectedTextStyle: WidgetStateProperty.all(AppTextStyles.navItem),
        selectedIconColor: WidgetStateProperty.all(AppColors.textPrimary),
        unselectedIconColor: WidgetStateProperty.all(AppColors.textSecondary),
      );
}
