import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Who builds a JDK. Both ship the same OpenJDK; the difference that matters
/// here is which API answers, and Adoptium is asked first.
enum JdkVendor {
  adoptium,
  azul;

  String get label => switch (this) {
    JdkVendor.adoptium => 'Eclipse Temurin',
    JdkVendor.azul => 'Azul Zulu',
  };
}

/// The long-term-support majors, for the badge when the API does not say.
///
/// Adoptium publishes its own list and that one wins; this is the fallback for
/// Zulu, whose package listing omits the support term.
// TODO: refresh as new LTS versions ship (25 was the last added).
const Set<int> kLtsMajors = {8, 11, 17, 21, 25};

/// A JDK build that can be downloaded.
class JdkRelease extends Equatable {
  const JdkRelease({
    required this.vendor,
    required this.major,
    required this.version,
    required this.downloadUrl,
    required this.fileName,
    this.checksum,
    this.sizeBytes,
    this.lts = false,
    this.packageUuid,
  });

  final JdkVendor vendor;
  final int major;

  /// Full version, e.g. `21.0.12`.
  final String version;

  /// An archive — never the installer.
  ///
  /// An archive needs no elevation, unpacks into a folder this app manages, and
  /// uninstalls by deleting that folder. An MSI does none of those.
  ///
  /// Which container it is depends on the platform the catalogue asked for:
  /// `.zip` on Windows, `.tar.gz` on Linux and macOS from Adoptium. Nothing may
  /// assume one — the installer reads the format off the bytes.
  final String downloadUrl;

  final String fileName;

  /// SHA-256 of the archive. Adoptium publishes it in the listing; Zulu only
  /// in its per-package detail, so it is null until that is fetched.
  final String? checksum;

  final int? sizeBytes;
  final bool lts;

  /// Azul's package id, which its detail endpoint needs to hand over the
  /// checksum. Null for Adoptium, which publishes one up front.
  final String? packageUuid;

  /// Where an install of this release lands under the managed folder.
  String get installFolderName =>
      '${vendor == JdkVendor.azul ? 'zulu' : 'temurin'}-$version';

  /// `212 MB`, or null when the API did not say.
  String? get displaySize {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return null;
    const mb = 1024 * 1024;
    return bytes >= mb
        ? '${(bytes / mb).round()} MB'
        : '${(bytes / 1024).round()} KB';
  }

  @override
  List<Object?> get props => [vendor, major, version, downloadUrl];
}

/// Which feature versions Adoptium publishes, and which of them are LTS.
class AdoptiumAvailability extends Equatable {
  const AdoptiumAvailability({required this.releases, required this.lts});

  final List<int> releases;
  final Set<int> lts;

  static const empty = AdoptiumAvailability(releases: [], lts: {});

  @override
  List<Object?> get props => [releases, lts];
}

/// Reads `/v3/info/available_releases`.
AdoptiumAvailability parseAdoptiumAvailability(String body) {
  final decoded = _decodeMap(body);
  if (decoded == null) return AdoptiumAvailability.empty;
  return AdoptiumAvailability(
    releases: _ints(decoded['available_releases']),
    lts: _ints(decoded['available_lts_releases']).toSet(),
  );
}

/// Reads `/v3/assets/latest/{major}/hotspot`, keeping the archive package.
///
/// Whatever container Adoptium serves for the os/arch the query pinned — a
/// `.zip` for Windows, a `.tar.gz` for Linux and macOS.
///
/// The endpoint answers with a list because it can span architectures; the
/// query already pins one, so in practice it holds a single entry.
List<JdkRelease> parseAdoptiumAssets(String body, {Set<int> lts = const {}}) {
  final decoded = _decodeList(body);
  if (decoded == null) return const [];

  final releases = <JdkRelease>[];
  for (final entry in decoded.whereType<Map<String, dynamic>>()) {
    final binary = entry['binary'];
    if (binary is! Map<String, dynamic>) continue;
    // The installer is an MSI; this app wants the archive.
    final package = binary['package'];
    if (package is! Map<String, dynamic>) continue;

    final link = package['link'] as String?;
    final name = package['name'] as String?;
    if (link == null || link.isEmpty) continue;

    final version = entry['version'];
    final major = version is Map<String, dynamic>
        ? (version['major'] as num?)?.toInt()
        : null;
    if (major == null) continue;

    final semver = version is Map<String, dynamic>
        ? version['openjdk_version'] as String?
        : null;

    releases.add(JdkRelease(
      vendor: JdkVendor.adoptium,
      major: major,
      version: _trimVersion(semver) ?? '$major',
      downloadUrl: link,
      fileName: name ?? link.split('/').last,
      checksum: package['checksum'] as String?,
      sizeBytes: (package['size'] as num?)?.toInt(),
      lts: lts.contains(major),
    ));
  }
  return releases;
}

/// Reads Azul's `/metadata/v1/zulu/packages/` listing.
///
/// Only the newest build per major survives: the endpoint returns every build
/// it knows and the picker offers one row per version.
List<JdkRelease> parseZuluPackages(String body, {Set<int> lts = kLtsMajors}) {
  final decoded = _decodeList(body);
  if (decoded == null) return const [];

  final newest = <int, JdkRelease>{};
  for (final entry in decoded.whereType<Map<String, dynamic>>()) {
    final url = entry['download_url'] as String?;
    if (url == null || !url.endsWith('.zip')) continue;

    final parts = _ints(entry['java_version']);
    if (parts.isEmpty) continue;
    final major = parts.first;

    final release = JdkRelease(
      vendor: JdkVendor.azul,
      major: major,
      version: parts.join('.'),
      downloadUrl: url,
      fileName: entry['name'] as String? ?? url.split('/').last,
      // The listing carries no checksum; the per-package detail endpoint does.
      sizeBytes: (entry['size'] as num?)?.toInt(),
      lts: lts.contains(major),
      packageUuid: entry['package_uuid'] as String?,
    );

    final existing = newest[major];
    if (existing == null || _isNewer(release.version, existing.version)) {
      newest[major] = release;
    }
  }
  return newest.values.toList();
}

/// Reads the SHA-256 out of Azul's `/packages/{uuid}` detail.
String? parseZuluChecksum(String body) {
  final decoded = _decodeMap(body);
  final hash = decoded?['sha256_hash'];
  return hash is String && hash.isNotEmpty ? hash : null;
}

/// Newest major first — the version someone is most likely to want is the one
/// they do not have to scroll to.
List<JdkRelease> sortReleases(List<JdkRelease> releases) {
  final sorted = [...releases];
  sorted.sort((a, b) {
    if (a.major != b.major) return b.major.compareTo(a.major);
    return _isNewer(a.version, b.version) ? -1 : 1;
  });
  return sorted;
}

/// `21.0.12+8-LTS` → `21.0.12`.
String? _trimVersion(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return raw.trim().split(RegExp(r'[+\-]')).first;
}

bool _isNewer(String a, String b) {
  final left = _components(a);
  final right = _components(b);
  for (var i = 0; i < left.length || i < right.length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l > r;
  }
  return false;
}

List<int> _components(String version) => [
  for (final part in version.split('.')) int.tryParse(part) ?? 0,
];

List<int> _ints(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is num) entry.toInt(),
  ];
}

Map<String, dynamic>? _decodeMap(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

List<dynamic>? _decodeList(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is List ? decoded : null;
  } catch (_) {
    return null;
  }
}
