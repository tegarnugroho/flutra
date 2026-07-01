import 'package:fluent_ui/fluent_ui.dart';

/// Central Fluent UI theme definitions for light and dark modes.
class AppTheme {
  const AppTheme._();

  /// Bright Android green — good on dark surfaces.
  static AccentColor get _darkAccent => AccentColor.swatch({
        'darkest': const Color(0xFF13351F),
        'darker': const Color(0xFF1E5231),
        'dark': const Color(0xFF2A7345),
        'normal': const Color(0xFF3DDC84),
        'light': const Color(0xFF63E39C),
        'lighter': const Color(0xFF8CEBB6),
        'lightest': const Color(0xFFB6F3D1),
      });

  /// Deeper green for light mode so buttons, selected states and accent text
  /// keep enough contrast against white surfaces (the bright green washed out).
  static AccentColor get _lightAccent => AccentColor.swatch({
        'darkest': const Color(0xFF0B3D22),
        'darker': const Color(0xFF115C33),
        'dark': const Color(0xFF157A44),
        'normal': const Color(0xFF1B9E57),
        'light': const Color(0xFF34B26E),
        'lighter': const Color(0xFF63C88F),
        'lightest': const Color(0xFF9FE0BC),
      });

  /// Kept for backwards compatibility (dark swatch).
  static AccentColor get accentColor => _darkAccent;

  static FluentThemeData light() => FluentThemeData(
        brightness: Brightness.light,
        accentColor: _lightAccent,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),
        cardColor: Colors.white,
      );

  static FluentThemeData dark() => FluentThemeData(
        brightness: Brightness.dark,
        accentColor: _darkAccent,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: const Color(0xFF1F1F1F),
      );
}
