import 'package:flutra/domain/entities/log_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogLine.parseLogcat (brief format)', () {
    test('parses priority, tag and message', () {
      final line = LogLine.parseLogcat('I/ActivityManager( 1234): Start proc');
      expect(line.priority, LogPriority.info);
      expect(line.tag, 'ActivityManager');
      expect(line.message, 'Start proc');
    });

    test('maps each priority letter', () {
      expect(LogLine.parseLogcat('E/Foo(1): x').priority, LogPriority.error);
      expect(LogLine.parseLogcat('W/Foo(1): x').priority, LogPriority.warn);
      expect(LogLine.parseLogcat('D/Foo(1): x').priority, LogPriority.debug);
      expect(LogLine.parseLogcat('V/Foo(1): x').priority, LogPriority.verbose);
      expect(LogLine.parseLogcat('F/Foo(1): x').priority, LogPriority.fatal);
    });

    test('falls back to unknown for non-logcat lines', () {
      final line = LogLine.parseLogcat('--------- beginning of main');
      expect(line.priority, LogPriority.unknown);
      expect(line.tag, isNull);
    });
  });

  group('LogPriority ranking', () {
    test('orders by severity for min-priority filtering', () {
      expect(LogPriority.error.rank, greaterThan(LogPriority.info.rank));
      expect(LogPriority.warn.rank, greaterThan(LogPriority.debug.rank));
      expect(LogPriority.fatal.rank, greaterThan(LogPriority.error.rank));
    });

    test('round-trips letters', () {
      expect(LogPriorityInfo.fromLetter('W'), LogPriority.warn);
      expect(LogPriority.warn.letter, 'W');
    });
  });
}
