import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Resolves the `flutter` executable, honouring a user-configured SDK path and
/// falling back to whatever is on the system PATH.
@lazySingleton
class FlutterLocator {
  String? _override;

  /// Sets a user-configured Flutter SDK root (null/empty = use PATH).
  set overrideFlutterRoot(String? path) =>
      _override = (path == null || path.trim().isEmpty) ? null : path.trim();

  String? get overrideRoot => _override;

  /// The flutter executable to invoke: the override's `bin/flutter` when valid,
  /// otherwise the bare command resolved via PATH.
  String get executable {
    final root = _override;
    if (root != null) {
      final exe = p.join(
          root, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter');
      if (File(exe).existsSync()) return exe;
    }
    return Platform.isWindows ? 'flutter.bat' : 'flutter';
  }

  /// The Flutter SDK root, or null if none can be found.
  ///
  /// [executable] deliberately falls back to the bare command name and lets
  /// the OS resolve it, which is all that running Flutter needs. Anything that
  /// wants the SDK *directory* — measuring its size, reading a file inside it —
  /// cannot work from a bare command name, so the PATH lookup happens here.
  ///
  /// Resolution order, first hit wins:
  ///  1. The override set from settings.
  ///  2. `FLUTTER_ROOT`.
  ///  3. The directory above whichever `bin/flutter` is on PATH.
  String? get root {
    for (final candidate in _candidateRoots()) {
      if (candidate != null && looksLikeFlutterSdk(candidate)) return candidate;
    }
    return null;
  }

  Iterable<String?> _candidateRoots() sync* {
    yield _override;
    yield Platform.environment['FLUTTER_ROOT'];
    // Windows environment lookups are case-insensitive in Platform.environment,
    // so 'PATH' covers 'Path' too.
    yield* rootsFromPathEntries(
      (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':'),
    );
  }

  /// Every SDK root a PATH could be pointing at, best guess first.
  ///
  /// Yields rather than returns the first hit because a PATH can hold a shim
  /// directory — scoop and chocolatey put one there — whose parent is not an
  /// SDK. The caller checks each in turn instead of giving up on the first.
  @visibleForTesting
  static Iterable<String> rootsFromPathEntries(Iterable<String> entries) sync* {
    final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
    for (final entry in entries) {
      // PATH entries can be quoted, and a trailing separator leaves an empty one.
      final dir = entry.trim().replaceAll('"', '');
      if (dir.isEmpty) continue;

      final exe = File(p.join(dir, name));
      if (!exe.existsSync()) continue;

      // A symlinked shim points at the real bin/flutter; following it lands
      // inside the SDK instead of next to the link.
      var resolved = exe.path;
      try {
        resolved = exe.resolveSymbolicLinksSync();
      } on FileSystemException {
        // Unreadable or dangling: fall back to the unresolved path, which is
        // still right for an ordinary install.
      }
      yield p.dirname(p.dirname(resolved));
    }
  }

  /// Whether [root] is a Flutter SDK rather than a folder that happens to hold
  /// something called flutter.
  ///
  /// `bin/internal` and `packages/flutter` ship with the SDK and exist before
  /// it is ever run — unlike `bin/cache`, which only appears after the first
  /// invocation and would miss a freshly cloned SDK.
  @visibleForTesting
  static bool looksLikeFlutterSdk(String root) =>
      Directory(p.join(root, 'bin', 'internal')).existsSync() &&
      Directory(p.join(root, 'packages', 'flutter')).existsSync();
}
