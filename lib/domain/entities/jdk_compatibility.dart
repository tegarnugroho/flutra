/// Which Gradle a JDK needs, and whether the JDK in force can build what the
/// installed Flutter would generate.
///
/// Deliberately a static table rather than anything derived from a project:
/// this page is about the machine, not about whatever repository happens to be
/// open, and the common failure — a brand-new JDK no released Gradle supports —
/// is knowable without reading a single build file.
library;

/// The first Gradle release that runs on a given JDK major version.
///
/// From Gradle's own compatibility matrix. A JDK newer than every entry here
/// is treated as unsupported, which is the honest answer: Gradle has to ship
/// support for a JDK, and the newest ones routinely have none.
// TODO: refine matrix as Gradle/AGP versions evolve.
const Map<int, String> kMinGradleForJdk = {
  8: '2.0',
  11: '5.0',
  17: '7.3',
  18: '7.5',
  19: '7.6',
  20: '8.1',
  21: '8.5',
  22: '8.8',
  23: '8.10',
  24: '8.14',
};

/// The Gradle version a `flutter create` project pins, by Flutter major.minor.
///
/// Only the boundaries are listed: a Flutter version between two entries uses
/// the lower one's Gradle. Flutter bumps this rarely, which is what makes a
/// table like this worth keeping.
// TODO: refine matrix as Gradle/AGP versions evolve.
const Map<String, String> kFlutterDefaultGradle = {
  '3.16': '7.6.3',
  '3.19': '8.3',
  '3.22': '8.4',
  '3.24': '8.7',
  '3.27': '8.10',
  '3.29': '8.12',
};

/// The lowest Gradle that runs on [major], or null when the table has never
/// heard of it.
String? minGradleForJdk(int major) {
  if (kMinGradleForJdk.containsKey(major)) return kMinGradleForJdk[major];
  final known = kMinGradleForJdk.keys.toList()..sort();
  // Below the table: anything ancient runs on anything, so no minimum applies.
  if (major < known.first) return null;
  // Above the table: no released Gradle is known to support it.
  if (major > known.last) return null;
  // Between entries: the nearest listed JDK below it is the closest answer.
  final below = known.lastWhere((k) => k < major);
  return kMinGradleForJdk[below];
}

/// Whether [major] is newer than every JDK the Gradle table knows about.
bool isUnknownNewJdk(int major) {
  final known = kMinGradleForJdk.keys.toList()..sort();
  return major > known.last;
}

/// The Gradle a project created by [flutterVersion] would use.
String? flutterDefaultGradle(String? flutterVersion) {
  if (flutterVersion == null) return null;
  final entries = kFlutterDefaultGradle.entries.toList()
    ..sort((a, b) => compareVersions(a.key, b.key));
  String? match;
  for (final entry in entries) {
    if (compareVersions(flutterVersion, entry.key) >= 0) match = entry.value;
  }
  return match;
}

/// One sentence about a JDK the toolchain cannot use, or null when there is
/// nothing to say.
///
/// Silence is the default: a hint that appears when everything is fine is a
/// hint nobody reads when it isn't.
String? jdkGradleWarning({required int? jdkMajor, String? flutterVersion}) {
  if (jdkMajor == null) return null;

  if (isUnknownNewJdk(jdkMajor)) {
    return 'JDK $jdkMajor is newer than any Gradle release this app knows '
        'about. Android builds are likely to fail until Gradle adds support — '
        'a JDK 17 or 21 install is the safe choice.';
  }

  final needed = minGradleForJdk(jdkMajor);
  final available = flutterDefaultGradle(flutterVersion);
  if (needed == null || available == null) return null;
  if (compareVersions(available, needed) >= 0) return null;

  return 'JDK $jdkMajor needs Gradle $needed, but Flutter $flutterVersion '
      'creates projects on Gradle $available. Android builds will fail unless '
      'the project raises its Gradle wrapper.';
}

/// Compares dotted version strings numerically: -1, 0 or 1.
///
/// Components are compared as numbers, so `8.10` is above `8.4` — a string
/// compare puts it below. Pre-release and build metadata is cut off rather
/// than ranked: `3.29.0-1.0.pre` is asking which table row applies to it, and
/// that is 3.29's.
int compareVersions(String a, String b) {
  final left = _components(a);
  final right = _components(b);
  for (var i = 0; i < left.length || i < right.length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}

List<int> _components(String version) {
  final release = version.trim().split(RegExp(r'[-+]')).first;
  return [
    for (final part in release.split('.'))
      int.tryParse(RegExp(r'^\d+').firstMatch(part)?.group(0) ?? '') ?? 0,
  ];
}
