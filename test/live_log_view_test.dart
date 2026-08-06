import 'package:flutra/domain/entities/log_line.dart';
import 'package:flutra/presentation/common/live_log_view.dart';
import 'package:flutra/presentation/theme/app_colors.dart';
import 'package:flutra/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(List<LogLine> lines) => FluentApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: ThemeMode.dark,
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: SizedBox(height: 400, child: LiveLogView(lines: lines)),
  ),
);

/// Every span of the row rendering [contains], flattened.
List<InlineSpan> _spansOf(WidgetTester tester, String contains) {
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .firstWhere((t) => (t.textSpan?.toPlainText() ?? '').contains(contains));
  final spans = <InlineSpan>[];
  text.textSpan!.visitChildren((span) {
    spans.add(span);
    return true;
  });
  return spans;
}

void main() {
  testWidgets('one selection covers the whole stream, not a single row',
      (tester) async {
    await tester.pumpWidget(
      _host([
        LogLine.parseLogcat('I/ActivityManager( 1234): first'),
        LogLine.parseLogcat('I/ActivityManager( 1234): second'),
      ]),
    );

    // Per-row SelectableText is what limited a drag to one line.
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('a JSON payload in a logcat message is re-indented and toned',
      (tester) async {
    await tester.pumpWidget(
      _host([
        LogLine.parseLogcat(
          'I/Sync( 1234): payload {"id": "abc", "count": 2}',
        ),
      ]),
    );

    final spans = _spansOf(tester, 'payload');
    final rendered = spans.map((s) => s.toPlainText()).join();
    expect(rendered, contains('{\n  "id": "abc",\n  "count": 2\n}'));

    TextStyle? styleOf(String text) => spans
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == text)
        .style;

    expect(styleOf('"id"')?.color, AppPalette.dark.jsonKey);
    expect(styleOf('"abc"')?.color, AppPalette.dark.jsonString);
    expect(styleOf('2')?.color, AppPalette.dark.jsonNumber);
  });

  testWidgets('a plain logcat line keeps its priority tone', (tester) async {
    await tester.pumpWidget(
      _host([LogLine.parseLogcat('E/Boom( 1234): it broke')]),
    );

    final spans = _spansOf(tester, 'it broke');
    expect(
      spans.whereType<TextSpan>().single.style?.color,
      AppPalette.dark.statusError,
    );
  });
}
