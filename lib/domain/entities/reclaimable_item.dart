import 'package:equatable/equatable.dart';

/// What sort of SDK component a reclaimable item is.
///
/// Distinct from [ReclaimableKind] in `storage_report.dart`, which answers a
/// different question — *which screen owns the cleanup* — and drives the
/// dashboard banner. This one names the package family, because the supersede
/// rule and the safety checks differ per family.
enum ReclaimKind {
  buildTools,
  platform,
  systemImage,
  sources,
  ndk,

  /// Nothing produces this yet: the emulator's caches are not sdkmanager
  /// packages, so they cannot be uninstalled the way everything else here is.
  // TODO(emulator-cache): decide whether `%USERPROFILE%\.android\cache` and
  // the per-AVD snapshots belong in this flow or in the AVD screen, which
  // already owns AVD deletion.
  emulatorCache,
}

extension ReclaimKindLabel on ReclaimKind {
  /// The group heading in the review list.
  String get label => switch (this) {
        ReclaimKind.buildTools => 'Build-tools',
        ReclaimKind.platform => 'Platforms',
        ReclaimKind.systemImage => 'System images',
        ReclaimKind.sources => 'Sources',
        ReclaimKind.ndk => 'NDK',
        ReclaimKind.emulatorCache => 'Emulator cache',
      };
}

/// How far one item got during a removal run.
enum ReclaimItemStatus { pending, running, done, failed, skipped }

/// One installed package the app believes is no longer needed.
class ReclaimableItem extends Equatable {
  const ReclaimableItem({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.folderPath,
    required this.reason,
    this.sizeBytes,
    this.supersededBy,
    this.warnings = const [],
    this.blockedReason,
  });

  /// The sdkmanager package path, e.g. `build-tools;34.0.0`. Also the id the
  /// uninstall is issued with.
  final String id;

  final ReclaimKind kind;

  /// "build-tools 34.0.0".
  final String displayName;

  /// Absolute folder the package occupies.
  final String folderPath;

  /// Why it is listed, e.g. "Superseded by build-tools 36.0.0".
  final String reason;

  /// Real on-disk size, null while the walk is still running.
  final int? sizeBytes;

  /// The package that replaced it, when there is one.
  final String? supersededBy;

  /// Consequences worth knowing before removing it. Never a blocker — an
  /// informed user is allowed to remove a version their projects pin.
  final List<String> warnings;

  /// Set when something depends on this item, which makes it unremovable.
  /// The review list shows it greyed out with this line.
  final String? blockedReason;

  bool get isBlocked => blockedReason != null;

  /// True for items nothing warns about — the ones safe to tick by default.
  bool get isSafeDefault => warnings.isEmpty && !isBlocked;

  ReclaimableItem copyWith({int? sizeBytes}) => ReclaimableItem(
        id: id,
        kind: kind,
        displayName: displayName,
        folderPath: folderPath,
        reason: reason,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        supersededBy: supersededBy,
        warnings: warnings,
        blockedReason: blockedReason,
      );

  @override
  List<Object?> get props => [
        id,
        kind,
        displayName,
        folderPath,
        reason,
        sizeBytes,
        supersededBy,
        warnings,
        blockedReason,
      ];
}

/// Everything one scan turned up.
class ReclaimableReport extends Equatable {
  const ReclaimableReport({required this.items, required this.scannedAt});

  final List<ReclaimableItem> items;
  final DateTime scannedAt;

  /// Items the user could actually act on.
  List<ReclaimableItem> get removable =>
      items.where((i) => !i.isBlocked).toList();

  /// Sum of the removable items whose size is known.
  int get totalReclaimableBytes =>
      removable.fold(0, (sum, i) => sum + (i.sizeBytes ?? 0));

  /// True while any size is still being measured.
  bool get isMeasuring => items.any((i) => i.sizeBytes == null);

  /// Grouped for the review list, in enum order.
  Map<ReclaimKind, List<ReclaimableItem>> get byKind {
    final grouped = <ReclaimKind, List<ReclaimableItem>>{};
    for (final kind in ReclaimKind.values) {
      final matching = items.where((i) => i.kind == kind).toList();
      if (matching.isNotEmpty) grouped[kind] = matching;
    }
    return grouped;
  }

  @override
  List<Object?> get props => [items, scannedAt];
}

/// Compares dotted or API-level version strings numerically.
///
/// Handles what the SDK actually uses: `34.0.0` (build-tools, ndk),
/// `android-34` (platforms, sources) and `android-TiramisuPrivacySandbox`
/// (preview levels, which sort after every numbered one because they are
/// newer than the release they follow).
int compareSdkVersions(String a, String b) {
  final na = _versionParts(a);
  final nb = _versionParts(b);
  if (na == null || nb == null) {
    // A preview level against a number: the preview is the newer thing.
    if (na == null && nb == null) return a.compareTo(b);
    return na == null ? 1 : -1;
  }
  for (var i = 0; i < na.length && i < nb.length; i++) {
    if (na[i] != nb[i]) return na[i].compareTo(nb[i]);
  }
  return na.length.compareTo(nb.length);
}

/// The numeric components of a version, or null when it has none.
List<int>? _versionParts(String raw) {
  final cleaned = raw.startsWith('android-') ? raw.substring(8) : raw;
  final parts = cleaned.split('.');
  final numbers = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null) return null;
    numbers.add(value);
  }
  return numbers.isEmpty ? null : numbers;
}
