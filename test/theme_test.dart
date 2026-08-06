import 'dart:io';
import 'dart:math' as math;

import 'package:flutra/presentation/shell/custom_title_bar.dart';
import 'package:flutra/presentation/theme/app_colors.dart';
import 'package:flutra/presentation/theme/app_text_styles.dart';
import 'package:flutra/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color fg, Color bg) {
  final a = _luminance(fg) + 0.05;
  final b = _luminance(bg) + 0.05;
  return a > b ? a / b : b / a;
}

void main() {
  group('palette', () {
    test('light and dark flip every surface and text tone', () {
      const light = AppPalette.light;
      const dark = AppPalette.dark;

      final flipping = <String, (Color, Color)>{
        'windowBg': (light.windowBg, dark.windowBg),
        'sidebarBg': (light.sidebarBg, dark.sidebarBg),
        'surfaceRaised': (light.surfaceRaised, dark.surfaceRaised),
        'logBg': (light.logBg, dark.logBg),
        'border': (light.border, dark.border),
        'borderStrong': (light.borderStrong, dark.borderStrong),
        'textPrimary': (light.textPrimary, dark.textPrimary),
        'textSecondary': (light.textSecondary, dark.textSecondary),
        'textTertiary': (light.textTertiary, dark.textTertiary),
        'textMuted': (light.textMuted, dark.textMuted),
        'captionPressed': (light.captionPressed, dark.captionPressed),
      };
      for (final entry in flipping.entries) {
        final (l, d) = entry.value;
        expect(l, isNot(d), reason: '${entry.key} must differ between themes');
      }
    });

    test('the close button stays red with a white glyph in both themes', () {
      for (final palette in const [AppPalette.light, AppPalette.dark]) {
        expect(palette.captionCloseHover, AppColors.captionCloseHover);
        expect(palette.captionClosePressed, AppColors.captionClosePressed);
        expect(
          _contrast(palette.captionCloseForeground, palette.captionCloseHover),
          greaterThan(4.5),
        );
      }
    });

    test('headings and body copy clear WCAG AA on their own surfaces', () {
      for (final palette in const [AppPalette.light, AppPalette.dark]) {
        for (final surface in [palette.windowBg, palette.sidebarBg]) {
          // Headings and row titles.
          expect(_contrast(palette.textPrimary, surface), greaterThan(7),
              reason: 'textPrimary on $surface');
          // Button labels, mono paths.
          expect(_contrast(palette.textTertiary, surface), greaterThan(7),
              reason: 'textTertiary on $surface');
          // Descriptions, detected paths, status lines.
          expect(_contrast(palette.textSecondary, surface), greaterThan(4.5),
              reason: 'textSecondary on $surface');
        }
      }
    });

    test('secondary text stays subordinate to primary', () {
      for (final palette in const [AppPalette.light, AppPalette.dark]) {
        final surface = palette.windowBg;
        expect(
          _contrast(palette.textSecondary, surface),
          lessThan(_contrast(palette.textPrimary, surface)),
        );
        expect(
          _contrast(palette.textMuted, surface),
          lessThan(_contrast(palette.textSecondary, surface)),
        );
      }
    });

    test('status tones stay readable on the content surface', () {
      for (final palette in const [AppPalette.light, AppPalette.dark]) {
        for (final status in [
          palette.statusOk,
          palette.statusWarn,
          palette.statusError,
        ]) {
          expect(_contrast(status, palette.windowBg), greaterThan(3.0));
        }
      }
    });

    test('JSON syntax tones stay readable on the log surface', () {
      for (final palette in const [AppPalette.light, AppPalette.dark]) {
        for (final tone in [
          palette.jsonKey,
          palette.jsonString,
          palette.jsonNumber,
          palette.jsonLiteral,
        ]) {
          expect(_contrast(tone, palette.logBg), greaterThan(4.5));
        }
      }
    });
  });

  group('theme wiring', () {
    test('both modes carry their palette and matching brightness', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      expect(light.extension<AppPalette>(), AppPalette.light);
      expect(dark.extension<AppPalette>(), AppPalette.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.scaffoldBackgroundColor, AppPalette.light.windowBg);
      expect(
        light.navigationPaneTheme.backgroundColor,
        AppPalette.light.sidebarBg,
      );
    });

    test('text styles resolve their tone from the palette', () {
      const lightText = AppTextStyles.fromPalette(AppPalette.light);
      const darkText = AppTextStyles.fromPalette(AppPalette.dark);

      expect(lightText.pageTitle.color, AppPalette.light.textPrimary);
      expect(darkText.pageTitle.color, AppPalette.dark.textPrimary);
      expect(lightText.heroTitle.color, AppPalette.light.textPrimary);
      expect(lightText.caption.color, AppPalette.light.textMuted);
      expect(lightText.monoPath.color, AppPalette.light.textTertiary);
      // Geometry is shared; only the tone moves.
      expect(lightText.pageTitle.fontSize, darkText.pageTitle.fontSize);
    });
  });

  group('title bar', () {
    Future<Color?> pumpBar(WidgetTester tester, ThemeMode mode) async {
      await tester.pumpWidget(
        FluentApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: const ScaffoldPage(
            padding: EdgeInsets.zero,
            content: CustomTitleBar(),
          ),
        ),
      );
      // The theme is animated, so a switch needs its transition to land before
      // the band shows its new colour.
      await tester.pumpAndSettle();
      final bar = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(CustomTitleBar),
              matching: find.byType(Container),
            )
            .first,
      );
      return bar.color;
    }

    testWidgets('takes its band colour from the active theme', (tester) async {
      expect(await pumpBar(tester, ThemeMode.dark), AppPalette.dark.sidebarBg);
      expect(await pumpBar(tester, ThemeMode.light), AppPalette.light.sidebarBg);
    });

    testWidgets('follows a live theme switch without a restart',
        (tester) async {
      expect(await pumpBar(tester, ThemeMode.dark), AppPalette.dark.sidebarBg);
      // Same widget tree, only themeMode changes — as the Settings dropdown does.
      expect(await pumpBar(tester, ThemeMode.light), AppPalette.light.sidebarBg);
      expect(await pumpBar(tester, ThemeMode.dark), AppPalette.dark.sidebarBg);
    });
  });

  group('no colour literals in the chrome', () {
    // The title bar, the shell and Settings must resolve everything through the
    // palette. A literal is allowed only where a comment above it says why.
    const guarded = <String>[
      'lib/presentation/shell/custom_title_bar.dart',
      'lib/presentation/shell/app_shell.dart',
      'lib/presentation/settings/settings_page.dart',
    ];
    final literal = RegExp(r'Color\(0x|Colors\.white|Colors\.black');

    for (final file in guarded) {
      test('$file has none', () {
        final lines = File(file).readAsLinesSync();
        final offenders = <String>[];
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!literal.hasMatch(line)) continue;
          if (line.trimLeft().startsWith('//')) continue;
          final justified = i > 0 && lines[i - 1].trimLeft().startsWith('//');
          if (!justified) offenders.add('${i + 1}: ${line.trim()}');
        }
        expect(offenders, isEmpty);
      });
    }
  });
}
