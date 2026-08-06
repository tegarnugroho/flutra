import 'package:injectable/injectable.dart';

/// Environment variables this session sets for every process the app spawns.
///
/// `setx` only reaches processes started *after* it runs, and never this one —
/// so a fix that sets `CHROME_EXECUTABLE` would not show up in the app's own
/// `flutter doctor` re-run until a restart. Recording it here and merging it
/// into each spawn closes that gap: the re-run sees the new value immediately,
/// while `setx` takes care of the user's other terminals.
///
/// Nothing here is persisted. It is a mirror of what the durable fix already
/// wrote, not a second source of truth.
@lazySingleton
class SessionEnvironment {
  final Map<String, String> _overrides = {};

  /// The overrides to merge into a spawn, or null when there are none —
  /// `Process.start` treats an empty map as "no extra variables" anyway, but a
  /// null keeps the call sites free of noise.
  Map<String, String>? get overrides =>
      _overrides.isEmpty ? null : Map.unmodifiable(_overrides);

  bool get isEmpty => _overrides.isEmpty;

  String? operator [](String name) => _overrides[name];

  void set(String name, String value) => _overrides[name] = value;

  /// Merges [extra] over the session values, for one specific call.
  Map<String, String>? merged(Map<String, String>? extra) {
    if (_overrides.isEmpty) return extra;
    if (extra == null || extra.isEmpty) return overrides;
    return {..._overrides, ...extra};
  }
}
