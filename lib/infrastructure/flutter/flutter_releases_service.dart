import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/failures.dart';
import '../../domain/entities/flutter_release.dart';

/// Fetches and caches Flutter's official release index.
///
/// The index is the source of truth for the version list: git tags in the local
/// checkout include pre-1.0 history and carry no channel or date information.
@lazySingleton
class FlutterReleasesService {
  /// Windows-only app, so the Windows index is the only one fetched.
  static const url = 'https://storage.googleapis.com/flutter_infra_release/'
      'releases/releases_windows.json';

  /// How long a cached copy is served without hitting the network.
  static const maxCacheAge = Duration(hours: 6);

  FlutterReleasesIndex? _memory;
  DateTime? _fetchedAt;
  bool _stale = false;

  /// When the served index was downloaded (not when it was read from disk).
  DateTime? get fetchedAt => _fetchedAt;

  /// True when the last successful load came from a cache older than
  /// [maxCacheAge] because the network was unreachable.
  bool get servingStaleCache => _stale;

  /// The release index, from memory, disk cache or the network.
  ///
  /// [forceRefresh] (the Refresh button) always re-fetches. On a network
  /// failure any cache — however old — is served instead, with
  /// [servingStaleCache] set; with no cache at all a [NetworkFailure] is thrown
  /// so the caller can fall back to git tags.
  Future<FlutterReleasesIndex> getReleases({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null && _isFresh(_fetchedAt)) {
      return _memory!;
    }

    if (!forceRefresh) {
      final cached = await _readCache();
      if (cached != null && _isFresh(cached.fetchedAt)) {
        _stale = false;
        return _remember(cached);
      }
    }

    try {
      final response = await Dio().get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final body = '${response.data}';
      final index = _parse(body);
      final now = DateTime.now();
      await _writeCache(body, now);
      _stale = false;
      return _remember(_CachedIndex(index, now));
    } catch (e) {
      // Offline: any cache beats no list at all.
      final cached = await _readCache();
      if (cached != null) {
        _stale = true;
        return _remember(cached);
      }
      throw NetworkFailure(
        'Could not download the Flutter release list.',
        suggestion: 'Check your connection, then press Refresh.',
        cause: e,
      );
    }
  }

  FlutterReleasesIndex _remember(_CachedIndex cached) {
    _memory = cached.index;
    _fetchedAt = cached.fetchedAt;
    return cached.index;
  }

  bool _isFresh(DateTime? at) =>
      at != null && DateTime.now().difference(at) < maxCacheAge;

  // TODO(archive-install): each release also publishes `archive` (a zip path
  // under [FlutterReleasesIndex.baseUrl]) and `sha256`. Downloading and
  // verifying that archive would let machines without git switch versions.
  // Out of scope here — switching stays a git checkout.

  /// The index is ~260 KB / ~720 entries; a plain decode measures in single-digit
  /// milliseconds, and the app has no compute/isolate convention, so this parses
  /// on the UI isolate.
  static FlutterReleasesIndex _parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return FlutterReleasesIndex.empty;
    return FlutterReleasesIndex.fromJson(decoded);
  }

  // ---- Disk cache ----------------------------------------------------------

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'flutter_releases_windows.json'));
  }

  Future<_CachedIndex?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!file.existsSync()) return null;
      final wrapper = jsonDecode(await file.readAsString());
      if (wrapper is! Map<String, dynamic>) return null;
      final at = DateTime.tryParse(wrapper['fetched_at'] as String? ?? '');
      final payload = wrapper['payload'];
      if (at == null || payload is! Map<String, dynamic>) return null;
      return _CachedIndex(FlutterReleasesIndex.fromJson(payload), at);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String body, DateTime fetchedAt) async {
    try {
      final file = await _cacheFile();
      await file.writeAsString(jsonEncode({
        'fetched_at': fetchedAt.toIso8601String(),
        'payload': jsonDecode(body),
      }));
    } catch (_) {
      // Best-effort cache; a failed write just means the next load re-fetches.
    }
  }
}

class _CachedIndex {
  const _CachedIndex(this.index, this.fetchedAt);

  final FlutterReleasesIndex index;
  final DateTime fetchedAt;
}
