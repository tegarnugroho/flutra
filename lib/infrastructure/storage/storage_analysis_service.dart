import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/storage_report.dart';
import '../sdk/flutter_locator.dart';
import '../sdk/sdk_locator.dart';

/// The inputs one scan needs, flattened so it can cross an isolate boundary.
///
/// Only primitives travel: the isolate gets paths, not services.
class _ScanRequest {
  const _ScanRequest({
    required this.sdkRoot,
    required this.flutterRoot,
    required this.avdHome,
  });

  final String? sdkRoot;
  final String? flutterRoot;
  final String? avdHome;
}

/// Measures what the toolchain occupies on disk and what looks reclaimable.
///
/// The scan walks tens of thousands of small files, so it runs in a background
/// isolate — on the UI isolate it would stall frames for seconds. Results are
/// cached to disk with a timestamp so opening the Dashboard is instant.
@lazySingleton
class StorageAnalysisService {
  StorageAnalysisService(this._sdk, this._flutter);

  final SdkLocator _sdk;
  final FlutterLocator _flutter;

  static final Logger _log = Logger('StorageAnalysisService');

  /// Past this age the cached report is refreshed in the background.
  static const Duration staleAfter = Duration(hours: 24);

  /// Largest items kept per category, for the expandable legend rows.
  static const int entriesPerCategory = 5;

  StorageReport? _memory;
  Future<StorageReport>? _inFlight;

  /// The last report, from memory or disk. Null when nothing has been scanned.
  Future<StorageReport?> cached() async {
    if (_memory != null) return _memory;
    try {
      final file = await _cacheFile();
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return _memory = StorageReport.fromJson(json);
    } catch (e) {
      _log.warning('could not read the cached report: $e');
      return null;
    }
  }

  bool isStale(StorageReport report) =>
      DateTime.now().difference(report.scannedAt) > staleAfter;

  /// Runs a scan, or joins the one already running.
  ///
  /// Concurrent callers share a single walk — the Dashboard can ask for a
  /// silent refresh while the user hits "Analyze again" without scanning twice.
  Future<StorageReport> analyze() {
    return _inFlight ??= _analyze().whenComplete(() => _inFlight = null);
  }

  Future<StorageReport> _analyze() async {
    final request = _ScanRequest(
      sdkRoot: _sdk.sdkRoot,
      flutterRoot: _flutter.root,
      avdHome: _avdHome(),
    );
    // Isolate.run copies the closure's captured values; only the plain strings
    // above travel, and the report comes back as plain data.
    final report = await Isolate.run(() => _scan(request));
    _memory = report;
    await _persist(report);
    return report;
  }

  /// Mirrors the emulator repository's resolution order.
  // TODO(paths): this duplicates `EmulatorRepositoryImpl._avdHome`. Lift that
  // into a shared locator when something else needs it a third time.
  String? _avdHome() {
    final env = Platform.environment;
    final explicit = env['ANDROID_AVD_HOME'];
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    final home = env['ANDROID_SDK_HOME'] ?? env['USERPROFILE'] ?? env['HOME'];
    if (home == null) return null;
    return p.join(home, '.android', 'avd');
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'storage-report.json'));
  }

  Future<void> _persist(StorageReport report) async {
    try {
      final file = await _cacheFile();
      await file.writeAsString(jsonEncode(report.toJson()));
    } catch (e) {
      _log.warning('could not cache the report: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Everything below runs inside the isolate. It touches only dart:io and the
// plain data types, so it can be exercised directly in tests.
// ---------------------------------------------------------------------------

StorageReport _scan(_ScanRequest request) {
  final slices = <StorageSlice>[];
  final skipped = <StorageCategory>[];
  final sdkRoot = request.sdkRoot;

  /// Names under the SDK root that get their own category.
  const known = {
    'system-images': StorageCategory.systemImages,
    'platforms': StorageCategory.platforms,
    'build-tools': StorageCategory.buildTools,
    'emulator': StorageCategory.emulatorTools,
    'platform-tools': StorageCategory.emulatorTools,
    'cmdline-tools': StorageCategory.emulatorTools,
    'tools': StorageCategory.emulatorTools,
    'ndk': StorageCategory.ndk,
    'ndk-bundle': StorageCategory.ndk,
  };

  if (sdkRoot != null && Directory(sdkRoot).existsSync()) {
    final totals = <StorageCategory, int>{};
    final entries = <StorageCategory, List<StorageEntry>>{};

    for (final child in Directory(sdkRoot).listSync().whereType<Directory>()) {
      final name = p.basename(child.path);
      final category = known[name] ?? StorageCategory.other;
      final bytes = directorySizeSync(child.path);
      totals.update(category, (v) => v + bytes, ifAbsent: () => bytes);

      // Grandchildren are the useful unit: one system image, one platform —
      // not the whole "system-images" folder.
      final grandchildren = category == StorageCategory.systemImages
          ? _imageEntries(child.path)
          : child
                .listSync()
                .whereType<Directory>()
                .map((d) => StorageEntry(
                  name: '$name/${p.basename(d.path)}',
                  bytes: directorySizeSync(d.path),
                  path: d.path,
                ))
                .toList();
      entries.putIfAbsent(category, () => []).addAll(
        grandchildren.isEmpty
            ? [StorageEntry(name: name, bytes: bytes, path: child.path)]
            : grandchildren,
      );
    }
    for (final entry in totals.entries) {
      slices.add(
        StorageSlice(
          category: entry.key,
          bytes: entry.value,
          entries: _topEntries(entries[entry.key] ?? const []),
        ),
      );
    }
  } else {
    skipped.addAll([
      StorageCategory.systemImages,
      StorageCategory.platforms,
      StorageCategory.buildTools,
      StorageCategory.emulatorTools,
    ]);
  }

  final flutterRoot = request.flutterRoot;
  if (flutterRoot != null && Directory(flutterRoot).existsSync()) {
    slices.add(
      StorageSlice(
        category: StorageCategory.flutterSdk,
        bytes: directorySizeSync(flutterRoot),
        entries: _topEntries(
          Directory(flutterRoot)
              .listSync()
              .whereType<Directory>()
              .map((d) => StorageEntry(
                name: p.basename(d.path),
                bytes: directorySizeSync(d.path),
                path: d.path,
              ))
              .toList(),
        ),
      ),
    );
  } else {
    skipped.add(StorageCategory.flutterSdk);
  }

  final avdHome = request.avdHome;
  final avdDirs = <Directory>[];
  if (avdHome != null && Directory(avdHome).existsSync()) {
    avdDirs.addAll(
      Directory(avdHome)
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.endsWith('.avd')),
    );
    final entries = avdDirs
        .map((d) => StorageEntry(
          name: p.basenameWithoutExtension(d.path),
          bytes: directorySizeSync(d.path),
          path: d.path,
        ))
        .toList();
    slices.add(
      StorageSlice(
        category: StorageCategory.avds,
        bytes: entries.fold(0, (sum, e) => sum + e.bytes),
        entries: _topEntries(entries),
      ),
    );
  } else {
    skipped.add(StorageCategory.avds);
  }

  return StorageReport(
    slices: slices.where((s) => s.bytes > 0).toList(),
    findings: _findings(sdkRoot, avdDirs, slices),
    scannedAt: DateTime.now(),
    skipped: skipped,
  );
}

/// System images nest three deep: `system-images/android-34/google_apis/x86_64`.
/// The ABI folder is the package, and its path is the sdkmanager id.
List<StorageEntry> _imageEntries(String root) {
  final entries = <StorageEntry>[];
  for (final platform in Directory(root).listSync().whereType<Directory>()) {
    for (final tag in platform.listSync().whereType<Directory>()) {
      for (final abi in tag.listSync().whereType<Directory>()) {
        entries.add(
          StorageEntry(
            name: 'system-images;${p.basename(platform.path)};'
                '${p.basename(tag.path)};${p.basename(abi.path)}',
            bytes: directorySizeSync(abi.path),
            path: abi.path,
          ),
        );
      }
    }
  }
  return entries;
}

List<StorageEntry> _topEntries(List<StorageEntry> entries) {
  final sorted = [...entries]..sort((a, b) => b.bytes.compareTo(a.bytes));
  return sorted
      .take(StorageAnalysisService.entriesPerCategory)
      .toList(growable: false);
}

/// Recursive size in bytes. Unreadable subtrees are skipped rather than
/// aborting the whole scan — a locked emulator file must not cost a report.
///
/// Public because the reclaim scanner measures the very same folders and must
/// not answer differently about them.
int directorySizeSync(String path) {
  var total = 0;
  try {
    for (final entity in Directory(path).listSync(recursive: true)) {
      if (entity is File) {
        try {
          total += entity.lengthSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

/// Things worth a second look. Nothing here deletes; the Dashboard only routes
/// to the screen that owns the cleanup.
List<ReclaimableFinding> _findings(
  String? sdkRoot,
  List<Directory> avdDirs,
  List<StorageSlice> slices,
) {
  final findings = <ReclaimableFinding>[];

  // Which images the AVDs actually reference, read from each config.ini.
  final referenced = <String>{};
  for (final dir in avdDirs) {
    final config = File(p.join(dir.path, 'config.ini'));
    if (!config.existsSync()) continue;
    try {
      for (final line in config.readAsLinesSync()) {
        // e.g. image.sysdir.1 = system-images\android-34\google_apis\x86_64\
        if (!line.startsWith('image.sysdir')) continue;
        final value = line.split('=').last.trim().replaceAll(r'\', '/');
        referenced.add(
          value.split('/').where((s) => s.isNotEmpty).join(';'),
        );
      }
    } catch (_) {}
  }

  final images = slices
      .where((s) => s.category == StorageCategory.systemImages)
      .expand((s) => s.entries);
  // Only claim an image is unused when at least one AVD said what it uses —
  // an unreadable config would otherwise mark every image as orphaned.
  if (referenced.isNotEmpty) {
    for (final image in images) {
      if (referenced.any((r) => image.name.endsWith(r))) continue;
      findings.add(
        ReclaimableFinding(
          kind: ReclaimableKind.unusedSystemImage,
          summary: '${image.name} unused by any AVD',
          bytes: image.bytes,
          target: image.name,
        ),
      );
    }
  }

  // "Last booted" has no recorded signal; the AVD folder's mtime moves when the
  // emulator writes its snapshot/userdata, which is the closest thing there is.
  // TODO(signal): if a future emulator writes a real timestamp, use it — mtime
  // also moves when the AVD is merely edited.
  final now = DateTime.now();
  for (final dir in avdDirs) {
    try {
      final age = now.difference(dir.statSync().modified);
      if (age.inDays < 90) continue;
      findings.add(
        ReclaimableFinding(
          kind: ReclaimableKind.staleAvd,
          summary: '"${p.basenameWithoutExtension(dir.path)}" not booted in '
              '${age.inDays} days',
          bytes: directorySizeSync(dir.path),
          target: p.basenameWithoutExtension(dir.path),
        ),
      );
    } catch (_) {}
  }

  if (sdkRoot != null) {
    final buildTools = Directory(p.join(sdkRoot, 'build-tools'));
    if (buildTools.existsSync()) {
      final versions = buildTools.listSync().whereType<Directory>().toList()
        ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      if (versions.length > 2) {
        for (final old in versions.skip(2)) {
          findings.add(
            ReclaimableFinding(
              kind: ReclaimableKind.oldBuildTools,
              summary: 'build-tools ${p.basename(old.path)} superseded',
              bytes: directorySizeSync(old.path),
              target: 'build-tools;${p.basename(old.path)}',
            ),
          );
        }
      }
    }
  }

  findings.sort((a, b) => b.bytes.compareTo(a.bytes));
  return findings;
}
