import 'package:android_sdk_manager/presentation/settings/dev_logs_page.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
