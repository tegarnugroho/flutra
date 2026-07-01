import 'package:android_sdk_manager/domain/entities/doctor_report.dart';
import 'package:android_sdk_manager/infrastructure/repositories/flutter_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = '''
[✓] Flutter (Channel stable, 3.44.1, on Microsoft Windows)
    • Flutter version 3.44.1 on channel stable
    • Framework revision 924134a44c
[✓] Windows Version (Installed version of Windows is version 10 or higher)
[✗] Android toolchain - develop for Android devices
    ✗ Unable to locate Android SDK.
      Install Android Studio from https://developer.android.com/studio
[!] Android Studio (not installed)
    • Android Studio not found
[✓] Connected device (1 available)
    • Windows (desktop) • windows • windows-x64
''';

void main() {
  group('FlutterRepositoryImpl.parse', () {
    final sections = FlutterRepositoryImpl.parse(_sample);

    test('splits every check into a section', () {
      expect(sections.length, 5);
      expect(sections[0].title, startsWith('Flutter'));
      expect(sections.last.title, startsWith('Connected device'));
    });

    test('maps markers to statuses', () {
      expect(sections[0].status, DoctorStatus.ok);
      expect(sections[2].status, DoctorStatus.error);
      expect(sections[3].status, DoctorStatus.warning);
    });

    test('collects indented detail lines under the right section', () {
      expect(sections[0].details, hasLength(2));
      expect(sections[0].details.first, contains('Flutter version 3.44.1'));
      expect(sections[2].details.any((l) => l.contains('Unable to locate')),
          isTrue);
    });

    test('treats the Windows "√" check glyph as passed', () {
      final windows = FlutterRepositoryImpl.parse(
        '[√] Flutter (Channel stable)\n    • ok\n[√] Windows Version',
      );
      expect(windows.every((s) => s.status == DoctorStatus.ok), isTrue);
    });

    test('report summary counts by status', () {
      final report = DoctorReport(sections: sections, rawOutput: _sample);
      expect(report.count(DoctorStatus.ok), 3);
      expect(report.count(DoctorStatus.error), 1);
      expect(report.count(DoctorStatus.warning), 1);
      expect(report.hasProblems, isTrue);
    });
  });
}
