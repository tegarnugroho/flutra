import 'package:fluent_ui/fluent_ui.dart';

/// Central Fluent UI theme definitions for light and dark modes.
class AppTheme {
  const AppTheme._();

  static const Color _accent = Color(0xFF3DDC84); // Android green.

  static AccentColor get accentColor => AccentColor.swatch({
        'darkest': const Color(0xFF13351F),
        'darker': const Color(0xFF1E5231),
        'dark': const Color(0xFF2A7345),
        'normal': _accent,
        'light': const Color(0xFF63E39C),
        'lighter': const Color(0xFF8CEBB6),
        'lightest': const Color(0xFFB6F3D1),
      });

  static FluentThemeData light() => FluentThemeData(
        brightness: Brightness.light,
        accentColor: accentColor,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: const Color(0xFFF3F3F3),
      );

  static FluentThemeData dark() => FluentThemeData(
        brightness: Brightness.dark,
        accentColor: accentColor,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: const Color(0xFF1F1F1F),
      );
}
