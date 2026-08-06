import 'package:flutra/domain/entities/storage_report.dart';
import 'package:flutra/presentation/dashboard/widgets/storage_panel.dart';
import 'package:flutter_test/flutter_test.dart';

const _gb = 1024 * 1024 * 1024;

StorageReport _report({
  List<StorageSlice> slices = const [],
  List<ReclaimableFinding> findings = const [],
  List<StorageCategory> skipped = const [],
}) => StorageReport(
  slices: slices,
  findings: findings,
  scannedAt: DateTime(2026, 1, 1),
  skipped: skipped,
);

void main() {
  group('report maths', () {
    test('totals every slice and orders them largest first', () {
      final report = _report(
        slices: const [
          StorageSlice(category: StorageCategory.avds, bytes: 6 * _gb),
          StorageSlice(category: StorageCategory.systemImages, bytes: 16 * _gb),
          StorageSlice(category: StorageCategory.flutterSdk, bytes: 7 * _gb),
        ],
      );

      expect(report.totalBytes, 29 * _gb);
      expect(
        report.sorted.map((s) => s.category),
        [
          StorageCategory.systemImages,
          StorageCategory.flutterSdk,
          StorageCategory.avds,
        ],
      );
    });

    test('reclaimable is the sum of findings, not of slices', () {
      final report = _report(
        slices: const [
          StorageSlice(category: StorageCategory.systemImages, bytes: 16 * _gb),
        ],
        findings: const [
          ReclaimableFinding(
            kind: ReclaimableKind.unusedSystemImage,
            summary: 'unused',
            bytes: 4 * _gb,
          ),
          ReclaimableFinding(
            kind: ReclaimableKind.staleAvd,
            summary: 'stale',
            bytes: 2 * _gb,
          ),
        ],
      );

      expect(report.reclaimableBytes, 6 * _gb);
      expect(report.reclaimableBytes, lessThan(report.totalBytes));
    });

    test('an empty report totals zero rather than throwing', () {
      expect(_report().totalBytes, 0);
      expect(_report().reclaimableBytes, 0);
      expect(_report().sorted, isEmpty);
    });
  });

  group('cache round-trip', () {
    test('survives json in both directions', () {
      final original = _report(
        slices: const [
          StorageSlice(
            category: StorageCategory.systemImages,
            bytes: 16 * _gb,
            entries: [
              StorageEntry(
                name: 'system-images;android-34;google_apis;x86_64',
                bytes: 4 * _gb,
                path: r'C:\Sdk\system-images\android-34\google_apis\x86_64',
              ),
            ],
          ),
        ],
        findings: const [
          ReclaimableFinding(
            kind: ReclaimableKind.oldBuildTools,
            summary: 'build-tools 33.0.1 superseded',
            bytes: _gb,
            target: 'build-tools;33.0.1',
          ),
        ],
        skipped: const [StorageCategory.ndk],
      );

      final restored = StorageReport.fromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.totalBytes, original.totalBytes);
      expect(restored.slices.first.entries.first.path, isNotNull);
      expect(restored.findings.first.target, 'build-tools;33.0.1');
      expect(restored.skipped, [StorageCategory.ndk]);
      expect(restored.scannedAt, original.scannedAt);
    });

    test('a cache written by a newer build degrades instead of crashing', () {
      // Unknown enum names must be dropped, not turned into a broken report.
      final restored = StorageReport.fromJson({
        'scannedAt': DateTime(2026).toIso8601String(),
        'slices': [
          {'category': 'somethingNew', 'bytes': 999},
          {'category': 'avds', 'bytes': 10},
        ],
        'findings': [
          {'kind': 'newHeuristic', 'summary': 'x', 'bytes': 5},
        ],
        'skipped': ['alsoNew'],
      });

      expect(restored, isNotNull);
      expect(restored!.slices, hasLength(1));
      expect(restored.findings, isEmpty);
      expect(restored.skipped, isEmpty);
    });

    test('a cache with no timestamp is rejected outright', () {
      expect(StorageReport.fromJson(const {}), isNull);
      expect(StorageReport.fromJson(const {'scannedAt': 'nonsense'}), isNull);
    });
  });

  group('formatting', () {
    test('sizes read the way a file manager writes them', () {
      expect(formatBytes(42), '42 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5 MB');
      expect(formatBytes((42.7 * _gb).round()), '42.7 GB');
    });

    test('ages stay coarse', () {
      final now = DateTime.now();
      expect(formatAge(now), 'just now');
      expect(formatAge(now.subtract(const Duration(minutes: 5))), '5 min ago');
      expect(formatAge(now.subtract(const Duration(hours: 2))), '2 hours ago');
      expect(formatAge(now.subtract(const Duration(days: 1))), '1 day ago');
    });
  });
}
