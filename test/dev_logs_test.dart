import 'package:flutra/presentation/settings/dev_logs_page.dart';
import 'package:flutra/presentation/settings/log_body_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text of every span of [kind], in order.
List<String> _of(LogBody body, LogSpanKind kind) =>
    body.spans.where((s) => s.kind == kind).map((s) => s.text).toList();

void main() {
  group('entry count formatting', () {
    test('groups thousands so a 6k log reads at a glance', () {
      expect(DevLogsPageFormat.thousands(0), '0');
      expect(DevLogsPageFormat.thousands(42), '42');
      expect(DevLogsPageFormat.thousands(999), '999');
      expect(DevLogsPageFormat.thousands(1000), '1,000');
      expect(DevLogsPageFormat.thousands(6400), '6,400');
      expect(DevLogsPageFormat.thousands(1234567), '1,234,567');
    });
  });

  group('log body formatting', () {
    test('a message without JSON is passed through untouched', () {
      final body = LogBodyFormat.parse('exec: flutter.bat devices --machine');

      expect(body.isJson, isFalse);
      expect(body.text, 'exec: flutter.bat devices --machine');
      expect(body.spans.single.kind, LogSpanKind.plain);
    });

    test('a brace that is only an argument is not treated as a payload', () {
      final body = LogBodyFormat.parse(r'exec: adb shell am start {intent}');

      expect(body.isJson, isFalse);
      expect(body.text, r'exec: adb shell am start {intent}');
    });

    test('the head before the payload stays plain', () {
      final body = LogBodyFormat.parse('output: {"id": "emulator-5554"}');

      expect(body.isJson, isTrue);
      expect(body.spans.first.kind, LogSpanKind.plain);
      expect(body.spans.first.text, 'output: ');
    });

    test('a payload is re-indented one value per line', () {
      final body = LogBodyFormat.parse(
        'output: [ { "name": "sdk gphone64", "port": 5554 } ]',
      );

      expect(body.text, '''
output: [
  {
    "name": "sdk gphone64",
    "port": 5554
  }
]''');
    });

    test('keys, strings, numbers and literals are told apart', () {
      final body = LogBodyFormat.parse(
        'output: {"id": "windows", "port": 5554, "emulator": false, '
        '"sdk": null}',
      );

      expect(_of(body, LogSpanKind.key), ['"id"', '"port"', '"emulator"',
        '"sdk"']);
      expect(_of(body, LogSpanKind.string), ['"windows"']);
      expect(_of(body, LogSpanKind.number), ['5554']);
      expect(_of(body, LogSpanKind.literal), ['false', 'null']);
    });

    test('a colon inside a string value never reads as a key separator', () {
      final body = LogBodyFormat.parse('output: {"sdk": "Windows 10: LTSC"}');

      expect(_of(body, LogSpanKind.key), ['"sdk"']);
      expect(_of(body, LogSpanKind.string), ['"Windows 10: LTSC"']);
    });

    test('an escaped quote does not end the string early', () {
      final body = LogBodyFormat.parse(r'output: {"path": "C:\\dev\" x"}');

      expect(_of(body, LogSpanKind.string), [r'"C:\\dev\" x"']);
    });

    test('empty objects and arrays stay on one line', () {
      final body = LogBodyFormat.parse('output: {"caps": {}, "tags": []}');

      expect(body.text, '''
output: {
  "caps": {},
  "tags": []
}''');
    });

    test('the runner\'s newline markers become real breaks', () {
      final body = LogBodyFormat.parse('output: line one ⏎ line two');

      expect(body.isJson, isFalse);
      expect(body.text, 'output: line one\nline two');
    });

    test('truncated output keeps its tail verbatim', () {
      final body = LogBodyFormat.parse(
        'output: {"id": "emulator-5554", "name": "sdk… (+22800 chars)',
      );

      expect(body.isJson, isTrue);
      expect(body.text, endsWith('… (+22800 chars)'));
      expect(_of(body, LogSpanKind.key), ['"id"', '"name"']);
    });

    test('collapsing keeps whole lines and drops the rest', () {
      final body = LogBodyFormat.parse(
        'output: {"a": 1, "b": 2, "c": 3, "d": 4}',
      );
      expect(body.lineCount, 6);

      final collapsed = body.take(3);
      expect(collapsed.lineCount, 3);
      expect(collapsed.text, '''
output: {
  "a": 1,
  "b": 2,''');
      expect(collapsed.isJson, isTrue);
    });

    test('a body already inside the limit is returned as is', () {
      final body = LogBodyFormat.parse('exec: flutter.bat doctor');

      expect(identical(body.take(8), body), isTrue);
    });
  });
}
