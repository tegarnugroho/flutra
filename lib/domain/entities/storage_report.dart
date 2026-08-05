import 'package:equatable/equatable.dart';

/// A slice of disk the toolchain occupies.
enum StorageCategory {
  systemImages,
  platforms,
  buildTools,
  emulatorTools,
  ndk,
  flutterSdk,
  avds,
  other,
}

extension StorageCategoryLabel on StorageCategory {
  String get label => switch (this) {
    StorageCategory.systemImages => 'System images',
    StorageCategory.platforms => 'Platforms',
    StorageCategory.buildTools => 'Build-tools',
    StorageCategory.emulatorTools => 'Emulator + tools',
    StorageCategory.ndk => 'NDK',
    StorageCategory.flutterSdk => 'Flutter SDK + cache',
    StorageCategory.avds => 'AVDs',
    StorageCategory.other => 'Other',
  };
}

/// One item inside a category — a system-image package, an AVD, a platform.
class StorageEntry extends Equatable {
  const StorageEntry({required this.name, required this.bytes, this.path});

  final String name;
  final int bytes;

  /// Absolute location, so a "Review" action can point at it.
  final String? path;

  @override
  List<Object?> get props => [name, bytes, path];
}

/// A category's total plus the largest things inside it.
class StorageSlice extends Equatable {
  const StorageSlice({
    required this.category,
    required this.bytes,
    this.entries = const [],
  });

  final StorageCategory category;
  final int bytes;

  /// Largest-first, capped by the scanner — enough for a legend to expand.
  final List<StorageEntry> entries;

  @override
  List<Object?> get props => [category, bytes, entries];
}

/// Something the user could plausibly delete, surfaced but never acted on.
class ReclaimableFinding extends Equatable {
  const ReclaimableFinding({
    required this.kind,
    required this.summary,
    required this.bytes,
    this.target,
  });

  final ReclaimableKind kind;

  /// One line, already phrased for display.
  final String summary;

  final int bytes;

  /// What the owning screen should focus — a package path or an AVD name.
  final String? target;

  @override
  List<Object?> get props => [kind, summary, bytes, target];
}

/// Which screen owns the cleanup for a finding.
enum ReclaimableKind { unusedSystemImage, staleAvd, oldBuildTools }

/// The result of one disk scan.
class StorageReport extends Equatable {
  const StorageReport({
    required this.slices,
    required this.findings,
    required this.scannedAt,
    this.skipped = const [],
  });

  final List<StorageSlice> slices;
  final List<ReclaimableFinding> findings;
  final DateTime scannedAt;

  /// Categories left out because their path was missing or unreadable.
  final List<StorageCategory> skipped;

  int get totalBytes =>
      slices.fold(0, (sum, slice) => sum + slice.bytes);

  int get reclaimableBytes =>
      findings.fold(0, (sum, finding) => sum + finding.bytes);

  /// Largest first — the order the bar and the legend both use.
  List<StorageSlice> get sorted {
    final list = [...slices]..sort((a, b) => b.bytes.compareTo(a.bytes));
    return list;
  }

  Map<String, dynamic> toJson() => {
    'scannedAt': scannedAt.toIso8601String(),
    'slices': [
      for (final slice in slices)
        {
          'category': slice.category.name,
          'bytes': slice.bytes,
          'entries': [
            for (final entry in slice.entries)
              {'name': entry.name, 'bytes': entry.bytes, 'path': entry.path},
          ],
        },
    ],
    'findings': [
      for (final finding in findings)
        {
          'kind': finding.kind.name,
          'summary': finding.summary,
          'bytes': finding.bytes,
          'target': finding.target,
        },
    ],
    'skipped': [for (final category in skipped) category.name],
  };

  static StorageReport? fromJson(Map<String, dynamic> json) {
    final scannedAt = DateTime.tryParse(json['scannedAt'] as String? ?? '');
    if (scannedAt == null) return null;

    T? byName<T extends Enum>(List<T> values, Object? name) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    return StorageReport(
      scannedAt: scannedAt,
      slices: [
        for (final raw in (json['slices'] as List? ?? []).cast<Map>())
          if (byName(StorageCategory.values, raw['category'])
              case final category?)
            StorageSlice(
              category: category,
              bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
              entries: [
                for (final e in (raw['entries'] as List? ?? []).cast<Map>())
                  StorageEntry(
                    name: e['name'] as String? ?? '',
                    bytes: (e['bytes'] as num?)?.toInt() ?? 0,
                    path: e['path'] as String?,
                  ),
              ],
            ),
      ],
      findings: [
        for (final raw in (json['findings'] as List? ?? []).cast<Map>())
          if (byName(ReclaimableKind.values, raw['kind']) case final kind?)
            ReclaimableFinding(
              kind: kind,
              summary: raw['summary'] as String? ?? '',
              bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
              target: raw['target'] as String?,
            ),
      ],
      skipped: [
        for (final name in (json['skipped'] as List? ?? []))
          if (byName(StorageCategory.values, name) case final category?)
            category,
      ],
    );
  }

  @override
  List<Object?> get props => [slices, findings, scannedAt, skipped];
}
