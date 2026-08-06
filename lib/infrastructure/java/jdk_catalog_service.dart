import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../../core/error/failures.dart';
import '../../core/platform/platform_service.dart';
import '../../domain/entities/jdk_release.dart';

/// The JDKs that can be downloaded, from Adoptium — or from Azul when Adoptium
/// will not answer.
///
/// Adoptium is asked first because its listing carries the archive's SHA-256,
/// so a download can be verified without a second request. Azul answers the
/// whole catalogue in one call but publishes checksums only per package, which
/// is why it is the fallback rather than the default.
@lazySingleton
class JdkCatalogService {
  JdkCatalogService(this._platform);

  final PlatformService _platform;

  static final Logger _log = Logger('JdkCatalogService');

  /// Matches the Flutter release index's window: the catalogue changes on a
  /// quarterly cadence, so anything shorter only adds requests.
  static const maxCacheAge = Duration(hours: 6);

  static const _timeout = Duration(seconds: 20);

  // TODO: x64 only, like the rest of the app. An arm64 Windows host would want
  // aarch64 here, and nothing detects the host architecture yet.
  static const _arch = 'x64';

  /// Cached per source, because the picker can switch between them and a
  /// second look at a list already fetched should not cost a request.
  final Map<JdkVendor, List<JdkRelease>> _memory = {};
  final Map<JdkVendor, DateTime> _fetchedAt = {};
  JdkVendor? _servedBy;

  /// Which API answered last, for the picker's footnote.
  JdkVendor? get servedBy => _servedBy;

  /// Every downloadable JDK, newest major first.
  ///
  /// [vendor] pins a source; null asks Adoptium first and falls back to Azul,
  /// which is what the picker's "Automatic" means. Throws a [NetworkFailure]
  /// only when everything asked for fails — a partial answer from Adoptium (one
  /// feature version that would not load) is still a list.
  Future<List<JdkRelease>> available({
    JdkVendor? vendor,
    bool forceRefresh = false,
  }) async {
    final order = vendor == null
        ? const [JdkVendor.adoptium, JdkVendor.azul]
        : [vendor];

    for (final source in order) {
      if (!forceRefresh && _isFresh(source)) {
        _servedBy = source;
        return _memory[source]!;
      }
      try {
        final releases = source == JdkVendor.adoptium
            ? await _fromAdoptium()
            : await _fromAzul();
        if (releases.isNotEmpty) return _remember(releases, source);
        _log.info('${source.label} returned nothing.');
      } catch (e) {
        _log.warning('${source.label} catalogue failed: $e');
      }
    }

    // A stale list beats an empty dialog; the download links do not rot.
    for (final source in order) {
      final cached = _memory[source];
      if (cached != null && cached.isNotEmpty) {
        _servedBy = source;
        return cached;
      }
    }

    throw const NetworkFailure(
      'Could not fetch the list of downloadable JDKs.',
      suggestion: 'Check your connection, then try again.',
    );
  }

  /// The SHA-256 of [release]'s archive.
  ///
  /// Adoptium ships it with the listing. Azul only exposes it per package, so
  /// that one costs a request — made here, right before a download, rather than
  /// for every row in a list nobody has chosen from yet.
  Future<String?> resolveChecksum(JdkRelease release) async {
    final known = release.checksum;
    if (known != null && known.isNotEmpty) return known;

    final uuid = release.packageUuid;
    if (release.vendor != JdkVendor.azul || uuid == null) return null;

    try {
      final response = await _dio().get<dynamic>(
        'https://api.azul.com/metadata/v1/zulu/packages/$uuid',
      );
      return parseZuluChecksum('${response.data}');
    } catch (e) {
      _log.warning('Azul checksum for $uuid failed: $e');
      return null;
    }
  }

  // ---- Adoptium ------------------------------------------------------------

  /// One call for the feature versions, then one per version for its newest
  /// build. Thirteen small requests in parallel, not thirteen round trips.
  Future<List<JdkRelease>> _fromAdoptium() async {
    final dio = _dio();
    final info = await dio.get<dynamic>(
      'https://api.adoptium.net/v3/info/available_releases',
    );
    final availability = parseAdoptiumAvailability('${info.data}');
    if (availability.releases.isEmpty) return const [];

    final assets = await Future.wait([
      for (final major in availability.releases)
        _adoptiumAssets(dio, major, availability.lts),
    ]);
    return sortReleases([for (final list in assets) ...list]);
  }

  /// A feature version that will not load is dropped rather than failing the
  /// catalogue: the other twelve are still worth showing.
  Future<List<JdkRelease>> _adoptiumAssets(
    Dio dio,
    int major,
    Set<int> lts,
  ) async {
    try {
      final response = await dio.get<dynamic>(
        'https://api.adoptium.net/v3/assets/latest/$major/hotspot',
        queryParameters: {
          'architecture': _arch,
          'image_type': 'jdk',
          'os': _adoptiumOs,
        },
      );
      return parseAdoptiumAssets('${response.data}', lts: lts);
    } catch (e) {
      _log.fine('Adoptium assets for $major failed: $e');
      return const [];
    }
  }

  String get _adoptiumOs => switch (_platform.operatingSystem) {
    'macos' => 'mac',
    'linux' => 'linux',
    _ => 'windows',
  };

  // ---- Azul ----------------------------------------------------------------

  /// One request, heavily filtered.
  ///
  /// Unfiltered this endpoint returns every OS, architecture, JRE and installer
  /// format Azul ships — megabytes of rows this app would throw away.
  Future<List<JdkRelease>> _fromAzul() async {
    final response = await _dio().get<dynamic>(
      'https://api.azul.com/metadata/v1/zulu/packages/',
      queryParameters: {
        'os': _azulOs,
        'arch': _arch,
        'java_package_type': 'jdk',
        'archive_type': 'zip',
        'javafx_bundled': 'false',
        'release_status': 'ga',
        'availability_types': 'CA',
        'latest': 'true',
        'page_size': '100',
      },
    );
    return sortReleases(parseZuluPackages('${response.data}'));
  }

  String get _azulOs => switch (_platform.operatingSystem) {
    'macos' => 'macos',
    'linux' => 'linux',
    _ => 'windows',
  };

  // ---- plumbing ------------------------------------------------------------

  Dio _dio() => Dio(
    BaseOptions(
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      // Both APIs answer JSON; taking it as plain text keeps parsing in the
      // pure functions the tests cover.
      responseType: ResponseType.plain,
    ),
  );

  bool _isFresh(JdkVendor vendor) {
    final at = _fetchedAt[vendor];
    return at != null &&
        _memory[vendor]?.isNotEmpty == true &&
        DateTime.now().difference(at) < maxCacheAge;
  }

  List<JdkRelease> _remember(List<JdkRelease> releases, JdkVendor vendor) {
    _memory[vendor] = releases;
    _fetchedAt[vendor] = DateTime.now();
    _servedBy = vendor;
    return releases;
  }
}
