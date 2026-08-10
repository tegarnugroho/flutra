import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import 'flutter_locator.dart';
import 'sdk_locator.dart';

/// What one scan looks at, flattened so it can cross an isolate boundary.
class _ScanRequest {
  const _ScanRequest({
    required this.roots,
    required this.kind,
    required this.budgetMs,
  });

  final List<String> roots;
  final SdkScanKind kind;

  /// Wall-clock ceiling for the walk. A slow network drive must not hang the
  /// scan indefinitely.
  final int budgetMs;
}

/// Which toolchain a scan is looking for.
enum SdkScanKind { flutter, android }

/// Finds SDK installations on disk when the environment does not say where they
/// are.
///
/// `ANDROID_HOME` and PATH only know about installs that were wired into the
/// shell. A Flutter checkout sitting in `D:\flutter`, or an SDK installed by
/// Android Studio under a second profile, is invisible to them — this is what
/// finds those.
///
/// The walk runs in a background isolate: it stats thousands of directories and
/// would stall frames on the UI isolate.
@lazySingleton
class SdkScanService {
  /// Directories below a start point that are never worth descending into.
  ///
  /// Windows and the package caches hold hundreds of thousands of entries and
  /// no SDK; skipping them is most of what keeps the scan quick.
  static const Set<String> skipNames = {
    'windows', 'winnt', r'$recycle.bin', 'system volume information',
    'node_modules', '.git', '.dart_tool', 'temp', 'tmp', 'cache', 'caches',
    'onedrive', 'perflogs', 'msys64', 'recovery', 'boot',
  };

  /// How deep to descend below each start point. An SDK is normally at
  /// `<drive>\<dir>\<dir>\flutter`, so three levels reaches it without walking
  /// whole source trees.
  static const int maxDepth = 3;

  /// Directories to stat before giving up, so a pathological tree cannot make
  /// the scan run forever.
  static const int maxVisits = 30000;

  static const Duration budget = Duration(seconds: 12);

  /// Where a scan starts: every drive root, plus the places installers and
  /// package managers use.
  ///
  /// Every point here is a Windows path — drive letters, `ProgramFiles`,
  /// chocolatey — so the joins use the Windows context rather than the host's.
  /// Off Windows the paths do not exist and the list comes back empty, which is
  /// what it did before; the context only stops the separators from being mixed.
  static List<String> startPoints({
    Map<String, String>? environment,
    bool Function(String)? exists,
  }) {
    final env = environment ?? Platform.environment;
    final dirExists = exists ?? (path) => Directory(path).existsSync();
    final points = <String>[];
    final win = p.windows;

    void add(String? path) {
      if (path == null || path.trim().isEmpty) return;
      final normalized = win.normalize(path.trim());
      if (!points.contains(normalized) && dirExists(normalized)) {
        points.add(normalized);
      }
    }

    // Drive roots. Letters rather than an API call: dart:io has no drive
    // enumeration, and 26 existence checks are cheaper than spawning a process.
    for (var letter = 'C'.codeUnitAt(0); letter <= 'Z'.codeUnitAt(0); letter++) {
      add('${String.fromCharCode(letter)}:\\');
    }

    final userProfile = env['USERPROFILE'];
    final localAppData = env['LOCALAPPDATA'];
    add(userProfile);
    add(localAppData);
    if (localAppData != null) add(win.join(localAppData, 'Android'));
    if (userProfile != null) {
      add(win.join(userProfile, 'scoop', 'apps'));
      add(win.join(userProfile, 'Android'));
      add(win.join(userProfile, 'Development'));
    }
    add(env['ProgramFiles']);
    add(env['ProgramFiles(x86)']);
    add(r'C:\ProgramData\chocolatey\lib');
    return points;
  }

  /// Every Flutter SDK root found on disk, best-guess order (shallowest first).
  Future<List<String>> findFlutterSdks() => _run(SdkScanKind.flutter);

  /// Every Android SDK root found on disk.
  Future<List<String>> findAndroidSdks() => _run(SdkScanKind.android);

  Future<List<String>> _run(SdkScanKind kind) {
    final request = _ScanRequest(
      roots: startPoints(),
      kind: kind,
      budgetMs: budget.inMilliseconds,
    );
    return Isolate.run(() => _scan(request));
  }
}

// ---------------------------------------------------------------------------
// Runs inside the isolate: dart:io and plain data only.
// ---------------------------------------------------------------------------

List<String> _scan(_ScanRequest request) {
  final clock = Stopwatch()..start();
  final found = <String>[];
  final seen = <String>{};
  var visits = 0;

  bool isSdk(String dir) => switch (request.kind) {
        SdkScanKind.flutter => FlutterLocator.looksLikeFlutterSdk(dir),
        SdkScanKind.android => SdkLocator.looksLikeAndroidSdk(dir),
      };

  // Breadth-first, so a match two levels down is reported before one five
  // levels down — the shallower path is nearly always the real install.
  var frontier = <String>[];
  for (final root in request.roots) {
    if (seen.add(p.normalize(root).toLowerCase())) frontier.add(root);
  }

  for (var depth = 0; depth <= SdkScanService.maxDepth; depth++) {
    final next = <String>[];
    for (final dir in frontier) {
      if (clock.elapsedMilliseconds > request.budgetMs ||
          visits > SdkScanService.maxVisits) {
        return found;
      }
      visits++;

      if (isSdk(dir)) {
        found.add(dir);
        // An SDK never nests inside another one; stop descending here.
        continue;
      }
      if (depth == SdkScanService.maxDepth) continue;

      final List<FileSystemEntity> children;
      try {
        children = Directory(dir).listSync(followLinks: false);
      } catch (_) {
        // Permission denied, a disconnected network drive, a locked folder:
        // all of them just mean "nothing here".
        continue;
      }
      for (final child in children) {
        if (child is! Directory) continue;
        final name = p.basename(child.path).toLowerCase();
        if (name.startsWith('.') && name != '.android') continue;
        if (SdkScanService.skipNames.contains(name)) continue;
        if (seen.add(p.normalize(child.path).toLowerCase())) {
          next.add(child.path);
        }
      }
    }
    if (next.isEmpty) break;
    frontier = next;
  }
  return found;
}
