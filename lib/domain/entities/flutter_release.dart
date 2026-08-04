import 'package:equatable/equatable.dart';

/// One entry from Flutter's official release index.
///
/// The real file is messy — several fields are absent on pre-2022 entries and
/// legacy versions carry a `v` prefix — so every optional field is nullable and
/// nothing is parsed strictly.
class FlutterRelease extends Equatable {
  const FlutterRelease({
    required this.hash,
    required this.channel,
    required this.version,
    this.dartSdkVersion,
    this.dartSdkArch,
    this.releaseDate,
    this.archive,
    this.sha256,
  });

  /// Full framework commit hash this release points at.
  final String hash;

  /// `stable`, `beta`, or the retired `dev`. Kept as a string so unknown future
  /// channels parse instead of throwing.
  final String channel;

  /// Raw version string as published, e.g. `3.13.3` or `v1.12.13+hotfix.5`.
  final String version;

  /// Raw Dart version. Stable publishes `3.12.2`; beta/dev publish
  /// `3.13.0 (build 3.13.0-282.3.beta)`. Absent on many older entries.
  final String? dartSdkVersion;

  final String? dartSdkArch;
  final DateTime? releaseDate;

  /// Relative path of the SDK zip under the index's `base_url`.
  final String? archive;
  final String? sha256;

  factory FlutterRelease.fromJson(Map<String, dynamic> json) {
    final date = json['release_date'];
    return FlutterRelease(
      hash: json['hash'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      version: json['version'] as String? ?? '',
      dartSdkVersion: json['dart_sdk_version'] as String?,
      dartSdkArch: json['dart_sdk_arch'] as String?,
      releaseDate: date is String ? DateTime.tryParse(date) : null,
      archive: json['archive'] as String?,
      sha256: json['sha256'] as String?,
    );
  }

  /// A synthetic entry for the offline git-tag fallback, which only knows the
  /// tag name.
  factory FlutterRelease.fromTag(String tag, String channel) =>
      FlutterRelease(hash: '', channel: channel, version: tag);

  /// The version without the legacy `v` prefix, for display and comparison.
  String get displayVersion =>
      version.startsWith('v') ? version.substring(1) : version;

  /// The git tag to check out. Verified against the local checkout: legacy tags
  /// really are stored with the `v` prefix (`v1.12.13+hotfix.5`), so the raw
  /// published string is the tag.
  String get gitTag => version;

  /// Dart version without the trailing `(build …)` qualifier.
  String? get displayDartVersion => dartSdkVersion?.split(' ').first;

  /// True for releases before Flutter 3.0, which the UI hides by default.
  bool get isLegacy {
    final major = int.tryParse(displayVersion.split('.').first);
    return major != null && major < 3;
  }

  @override
  List<Object?> get props => [hash, channel, version, releaseDate];
}

/// The channel → hash map of the newest release per channel.
class CurrentRelease extends Equatable {
  const CurrentRelease(this.hashes);

  /// Keyed by channel name. A [Map] rather than fixed fields so an unknown
  /// future channel doesn't break parsing.
  final Map<String, String> hashes;

  factory CurrentRelease.fromJson(Map<String, dynamic> json) => CurrentRelease({
        for (final entry in json.entries)
          if (entry.value is String) entry.key: entry.value as String,
      });

  String? operator [](String channel) => hashes[channel];

  @override
  List<Object?> get props => [hashes];
}

/// The parsed `releases_windows.json` index.
class FlutterReleasesIndex extends Equatable {
  const FlutterReleasesIndex({
    required this.baseUrl,
    required this.currentRelease,
    required this.releases,
  });

  final String baseUrl;
  final CurrentRelease currentRelease;
  final List<FlutterRelease> releases;

  static const empty = FlutterReleasesIndex(
    baseUrl: '',
    currentRelease: CurrentRelease({}),
    releases: [],
  );

  factory FlutterReleasesIndex.fromJson(Map<String, dynamic> json) {
    final raw = json['releases'];
    return FlutterReleasesIndex(
      baseUrl: json['base_url'] as String? ?? '',
      currentRelease: CurrentRelease.fromJson(
          (json['current_release'] as Map?)?.cast<String, dynamic>() ?? const {}),
      releases: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(FlutterRelease.fromJson)
              .where((r) => r.version.isNotEmpty)
              .toList()
          : const [],
    );
  }

  /// Releases on [channel], newest first.
  ///
  /// Re-released versions (the same `(version, channel)` published twice, e.g.
  /// stable 3.13.3) collapse to the entry with the latest release date. The
  /// same hash appearing in several channels is NOT deduped — a promoted
  /// release is a real entry in each channel's list. The file's own ordering
  /// is not trusted; entries are re-sorted by date.
  List<FlutterRelease> forChannel(String channel) {
    final byVersion = <String, FlutterRelease>{};
    for (final release in releases) {
      if (release.channel != channel) continue;
      final existing = byVersion[release.version];
      if (existing == null || _isNewer(release, existing)) {
        byVersion[release.version] = release;
      }
    }
    final list = byVersion.values.toList()
      ..sort((a, b) => _isNewer(a, b) ? -1 : 1);
    return list;
  }

  /// The release [hash] points at, or null when the commit isn't published
  /// (a custom build or a fork).
  FlutterRelease? byHash(String hash) {
    if (hash.isEmpty) return null;
    for (final release in releases) {
      if (release.hash == hash) return release;
    }
    return null;
  }

  /// The newest release on [channel] per the index's own `current_release`.
  FlutterRelease? latestFor(String channel) {
    final hash = currentRelease[channel];
    if (hash == null) return null;
    for (final release in releases) {
      if (release.hash == hash && release.channel == channel) return release;
    }
    // Promoted releases can be listed under a different channel only.
    return byHash(hash);
  }

  /// Dateless entries (the git-tag fallback) sort last.
  static bool _isNewer(FlutterRelease a, FlutterRelease b) {
    final da = a.releaseDate;
    final db = b.releaseDate;
    if (da == null) return false;
    if (db == null) return true;
    return da.isAfter(db);
  }

  @override
  List<Object?> get props => [baseUrl, currentRelease, releases];
}
