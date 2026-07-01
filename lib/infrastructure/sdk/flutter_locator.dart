import 'dart:io';

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
}
