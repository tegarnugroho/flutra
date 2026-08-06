import 'package:android_sdk_manager/domain/entities/doctor_issue.dart';
import 'package:android_sdk_manager/domain/entities/doctor_report.dart';
import 'package:android_sdk_manager/infrastructure/doctor/doctor_fix_service.dart';
import 'package:flutter_test/flutter_test.dart';

List<DoctorIssue> match(String category, List<String> lines,
        {DoctorStatus status = DoctorStatus.warning}) =>
    issuesFor(category: category, status: status, detailLines: lines);

void main() {
  group('issuesFor', () {
    test('a passing check never has an issue, whatever its lines say', () {
      final issues = match(
        'Android toolchain',
        ['X Android license status unknown.'],
        status: DoctorStatus.ok,
      );
      expect(issues, isEmpty);
    });

    test('an unresolved check has no issue either', () {
      expect(
        issuesFor(
          category: 'Android toolchain',
          status: null,
          detailLines: const ['X Android license status unknown.'],
        ),
        isEmpty,
      );
    });

    test('matches the licence line flutter actually prints', () {
      final issues = match('Android toolchain', [
        'X Android license status unknown.',
        '  Run `flutter doctor --android-licenses` to accept the SDK licenses.',
      ]);
      expect(issues.map((i) => i.id), ['android_licenses']);
      expect(issues.single.kind, FixKind.auto);
    });

    test('collects every problem in one category', () {
      final issues = match('Android toolchain', [
        'X cmdline-tools component is missing',
        'X Android licenses not accepted',
      ]);
      // Both are real, separate jobs — one button each.
      expect(issues.map((i) => i.id),
          containsAll(['android_licenses', 'cmdline_tools_missing']));
      expect(issues, hasLength(2));
    });

    test('does not match a pattern from a different category', () {
      // The Chrome wording under the Android section must not fire.
      final issues = match('Android toolchain', [
        'X Cannot find Chrome executable at ...',
      ]);
      expect(issues.single.id, 'unknown');
    });

    test('an unrecognised failure falls back to the docs', () {
      final issues = match('Network resources', [
        'X A network error occurred while checking "https://pub.dev/"',
      ]);
      expect(issues.single.id, 'unknown');
      expect(issues.single.kind, FixKind.redirect);
      expect(issues.single.url, kWindowsInstallDocs);
      expect(issues.single.actionLabel, 'View docs');
    });

    test('matching ignores case, as the real output varies', () {
      final issues = match('Visual Studio', [
        'X visual studio not installed; this is necessary to develop for '
            'Windows.',
      ]);
      expect(issues.single.id, 'vs_missing');
    });

    test('every registry entry is uniquely identified', () {
      final ids = kDoctorIssues.map((i) => i.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('the incomplete-VS pattern wins over the not-installed one', () {
      // Registry order decides, and a toolchain complaint is the more
      // specific reading of a Visual Studio failure.
      final issues = match('Visual Studio', [
        'X Visual Studio is missing necessary components. Please re-run the '
            'installer for the "Desktop development with C++" workload.',
      ]);
      expect(issues.first.id, 'vs_incomplete');
    });
  });

  group('SelectJdkFix.parseMajorVersion', () {
    test('reads the modern scheme', () {
      expect(
        SelectJdkFix.parseMajorVersion('openjdk version "17.0.20" 2025-10-21'),
        17,
      );
      expect(SelectJdkFix.parseMajorVersion('java version "21.0.1"'), 21);
    });

    test('reads Java 8 as 8, not as 1', () {
      // "1.8.0_401" must not look newer than nothing at all.
      expect(SelectJdkFix.parseMajorVersion('java version "1.8.0_401"'), 8);
    });

    test('gives up on output with no version in it', () {
      expect(SelectJdkFix.parseMajorVersion('not a jvm'), isNull);
    });
  });

  group('SelectBrowserFix.candidatePaths', () {
    test('covers Chrome, Brave and Edge, including the per-user install', () {
      final paths = SelectBrowserFix.candidatePaths(
        environment: {'LOCALAPPDATA': r'C:\Users\dev\AppData\Local'},
      );
      expect(paths.any((p) => p.contains('Google')), isTrue);
      expect(paths.any((p) => p.contains('Brave')), isTrue);
      expect(paths.any((p) => p.contains('Edge')), isTrue);
      expect(
        paths,
        contains(r'C:\Users\dev\AppData\Local\Google\Chrome\Application\chrome.exe'),
      );
    });

    test('drops the per-user path when LOCALAPPDATA is unset', () {
      final paths = SelectBrowserFix.candidatePaths(environment: const {});
      expect(paths.any((p) => p.contains('AppData')), isFalse);
    });
  });
}
