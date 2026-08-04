import 'package:android_sdk_manager/domain/entities/doctor_report.dart';
import 'package:android_sdk_manager/infrastructure/doctor/doctor_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captured from a real run on Windows: the marker really is `√` (U+221A) and
/// every heading carries its own elapsed time.
const _windowsSample = '''
[√] Flutter (Channel stable, 3.44.8, on Microsoft Windows [Version 10.0.19044], locale en-ID) [353ms]
    • Flutter version 3.44.8 on channel stable at C:\\Dev\\SDK\\flutter
    • Framework revision 058e0af2c2 (12 days ago)
[√] Windows Version (10 Enterprise LTSC 64-bit, 21H2, 2009) [3.4s]
[√] Android toolchain - develop for Android devices (Android SDK version 36.0.0) [1,821ms]
    • Android SDK at C:\\Users\\pc\\AppData\\Local\\Android\\Sdk
[!] Android Studio (not installed) [12ms]
    • Android Studio not found
[X] Connected device [332ms]
    X No devices available
''';

/// Feeds [text] line by line, the way the runner does.
List<DoctorEvent> _run(String text) {
  final parser = DoctorStreamParser();
  final events = <DoctorEvent>[];
  for (final line in text.trim().split('\n')) {
    events.addAll(parser.feed(line));
  }
  events.addAll(parser.flush());
  return events;
}

List<DoctorCheckResolved> _resolved(String text) =>
    _run(text).whereType<DoctorCheckResolved>().toList();

void main() {
  group('markers', () {
    test('accepts the Windows console glyph and the unicode tick', () {
      expect(DoctorStreamParser.statusFromMarker('√'), DoctorStatus.ok);
      expect(DoctorStreamParser.statusFromMarker('✓'), DoctorStatus.ok);
      expect(DoctorStreamParser.statusFromMarker('!'), DoctorStatus.warning);
      expect(DoctorStreamParser.statusFromMarker('X'), DoctorStatus.error);
      expect(DoctorStreamParser.statusFromMarker('x'), DoctorStatus.error);
      expect(DoctorStreamParser.statusFromMarker('✗'), DoctorStatus.error);
      expect(DoctorStreamParser.statusFromMarker('?'), DoctorStatus.info);
    });

    test('maps every check in a captured Windows run', () {
      final resolved = _resolved(_windowsSample);
      expect(resolved, hasLength(5));
      expect(resolved[0].status, DoctorStatus.ok);
      expect(resolved[3].status, DoctorStatus.warning);
      expect(resolved[4].status, DoctorStatus.error);
    });
  });

  group('elapsed suffix', () {
    test('parses ms, seconds and thousands separators', () {
      expect(DoctorStreamParser.parseElapsed('Flutter [353ms]'),
          const Duration(milliseconds: 353));
      expect(DoctorStreamParser.parseElapsed('Windows Version [3.4s]'),
          const Duration(milliseconds: 3400));
      expect(DoctorStreamParser.parseElapsed('Android toolchain [1,821ms]'),
          const Duration(milliseconds: 1821));
    });

    test('is null when the heading has no timing', () {
      expect(DoctorStreamParser.parseElapsed('Flutter (Channel stable)'), isNull);
    });

    test('is stripped out of the stored title', () {
      final first = _resolved(_windowsSample).first;
      expect(first.title, isNot(contains('353ms')));
      expect(first.title, startsWith('Flutter (Channel stable'));
      expect(first.elapsed, const Duration(milliseconds: 353));
    });
  });

  group('check names', () {
    test('drops the parenthetical and the "- develop for…" tail', () {
      expect(DoctorStreamParser.checkName('Flutter (Channel stable, 3.44.8)'),
          'Flutter');
      expect(
          DoctorStreamParser.checkName(
              'Android toolchain - develop for Android devices (SDK 36.0.0)'),
          'Android toolchain');
      expect(DoctorStreamParser.checkName('Network resources'),
          'Network resources');
    });

    test('keeps an unknown future check rather than dropping it', () {
      final resolved = _resolved('[√] Quantum toolchain (experimental) [10ms]');
      expect(resolved.single.name, 'Quantum toolchain');
    });
  });

  group('details', () {
    test('attach to the check above them', () {
      final events = _run(_windowsSample);
      final details = events.whereType<DoctorCheckDetails>().toList();
      final flutter = details.firstWhere((d) => d.name == 'Flutter');
      expect(flutter.lines, hasLength(2));
      expect(flutter.lines.first, contains('Flutter version 3.44.8'));
    });

    test('indented marker lines are details, not new checks', () {
      final resolved = _resolved(_windowsSample);
      // "    X No devices available" must not become its own check.
      expect(resolved.map((r) => r.name), isNot(contains('No devices')));
      final details = _run(_windowsSample)
          .whereType<DoctorCheckDetails>()
          .firstWhere((d) => d.name == 'Connected device');
      expect(details.lines.single, contains('No devices available'));
    });

    test('the last check still gets its details on flush', () {
      final events = _run('[√] Flutter [1ms]\n    • only line');
      expect(events.whereType<DoctorCheckDetails>().single.lines,
          ['• only line']);
    });
  });

  group('resolution order', () {
    test('a check resolves as soon as its marker line arrives', () {
      final parser = DoctorStreamParser();
      final first = parser.feed('[√] Flutter (Channel stable) [353ms]');
      // Resolved immediately — not held back waiting for detail lines.
      expect(first.whereType<DoctorCheckResolved>(), hasLength(1));
      expect(parser.feed('    • detail'), isEmpty);
    });

    test('summary is the parenthetical part of the heading', () {
      final resolved = _resolved(_windowsSample);
      expect(resolved[1].summary, '10 Enterprise LTSC 64-bit, 21H2, 2009');
      expect(resolved.last.summary, isNull);
    });
  });
}
