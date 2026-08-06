import 'package:equatable/equatable.dart';

/// Where a JDK was discovered. Shown on the tile, because "which of these is
/// the one my build uses" is usually answered by how it got on the list.
enum JdkSource {
  /// `HKLM\SOFTWARE\JavaSoft\JDK` — installed by an official installer.
  registry,

  /// Found by enumerating the usual install folders.
  disk,

  /// `%USERPROFILE%\.jdks`, where IntelliJ and Android Studio put the JDKs
  /// they download.
  jdksDir,

  /// The JBR bundled with Android Studio.
  androidStudio,

  /// Downloaded and unpacked by this app.
  managed,
  javaHome,
  path,

  /// Added by hand through the folder picker.
  manual;

  String get label => switch (this) {
    JdkSource.registry => 'registry',
    JdkSource.disk => 'installed',
    JdkSource.jdksDir => '.jdks',
    JdkSource.androidStudio => 'Android Studio',
    JdkSource.managed => 'Flutra',
    JdkSource.javaHome => 'JAVA_HOME',
    JdkSource.path => 'PATH',
    JdkSource.manual => 'manual',
  };
}

/// Whether an entry can actually build anything.
enum JdkValidity {
  valid,

  /// `java` but no `javac` — a runtime, not a kit.
  jreOnly,

  /// The version could not be read at all.
  invalid;

  /// The muted suffix on the tile, or null when nothing is wrong.
  String? get reason => switch (this) {
    JdkValidity.valid => null,
    JdkValidity.jreOnly => 'JRE only',
    JdkValidity.invalid => 'invalid',
  };
}

/// What decides which JDK a build actually gets.
enum ActiveJdkSource {
  /// `flutter config --jdk-dir`, which overrides everything else for Flutter.
  flutterConfig,
  javaHome,
  path;

  String get label => switch (this) {
    ActiveJdkSource.flutterConfig => 'flutter config',
    ActiveJdkSource.javaHome => 'JAVA_HOME',
    ActiveJdkSource.path => 'PATH',
  };
}

/// One JDK installation on this machine.
class Jdk extends Equatable {
  const Jdk({
    required this.path,
    required this.source,
    this.validity = JdkValidity.valid,
    this.version,
    this.vendor,
    this.arch,
  });

  /// Absolute, symlink-resolved JDK root — the value `JAVA_HOME` would take.
  final String path;

  final JdkSource source;
  final JdkValidity validity;

  /// Full version as the JDK reports it, e.g. `17.0.11`.
  final String? version;

  /// `IMPLEMENTOR` from the release file, e.g. `Eclipse Adoptium`.
  final String? vendor;

  /// `OS_ARCH`, e.g. `x86_64`.
  final String? arch;

  int? get major => version == null ? null : javaMajorVersion(version!);

  /// `JDK 17`, or just `JDK` when the version could not be read.
  String get displayName => major == null ? 'JDK' : 'JDK $major';

  /// Whether this entry can be made the active JDK.
  bool get isSelectable => validity == JdkValidity.valid;

  Jdk copyWith({JdkSource? source, JdkValidity? validity}) => Jdk(
    path: path,
    source: source ?? this.source,
    validity: validity ?? this.validity,
    version: version,
    vendor: vendor,
    arch: arch,
  );

  @override
  List<Object?> get props => [path, source, validity, version, vendor, arch];
}

/// The JDK a build will actually use, and what decided that.
class ActiveJdk extends Equatable {
  const ActiveJdk(this.jdk, this.source);

  final Jdk jdk;
  final ActiveJdkSource source;

  @override
  List<Object?> get props => [jdk, source];
}

/// Picks the JDK in force, in the order the toolchain resolves it.
///
/// Flutter's own setting wins because it is the one that survives a shell that
/// never exported anything; `JAVA_HOME` is next because Gradle reads it; PATH
/// is the last resort and the least deliberate.
ActiveJdk? resolveActiveJdk(
  List<Jdk> jdks, {
  String? flutterJdkDir,
  String? javaHome,
  String? pathJdk,
}) {
  Jdk? find(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    for (final jdk in jdks) {
      if (samePath(jdk.path, path)) return jdk;
    }
    return null;
  }

  final configured = find(flutterJdkDir);
  if (configured != null) return ActiveJdk(configured, ActiveJdkSource.flutterConfig);
  final home = find(javaHome);
  if (home != null) return ActiveJdk(home, ActiveJdkSource.javaHome);
  final onPath = find(pathJdk);
  if (onPath != null) return ActiveJdk(onPath, ActiveJdkSource.path);
  return null;
}

/// Compares two filesystem paths for identity.
///
/// Case-insensitive and separator-agnostic, and a trailing slash names the same
/// directory — the same path arrives spelled three ways from the registry, the
/// environment and a folder picker.
bool samePath(String a, String b) => _normalisePath(a) == _normalisePath(b);

String _normalisePath(String value) {
  var path = value.trim().replaceAll('/', r'\');
  while (path.length > 1 && path.endsWith(r'\')) {
    path = path.substring(0, path.length - 1);
  }
  return path.toLowerCase();
}

/// Reads a JDK `release` file: `KEY="value"` lines, one per line.
Map<String, String> parseReleaseFile(String content) {
  final values = <String, String>{};
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;
    final key = trimmed.substring(0, separator).trim();
    var value = trimmed.substring(separator + 1).trim();
    if (value.length > 1 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    if (key.isNotEmpty) values[key] = value;
  }
  return values;
}

/// `17.0.11` → 17, `1.8.0_401` → 8, `21` → 21.
///
/// Java 8 and earlier report `1.x`, where the major version is the second
/// component; everything since reports it first.
int? javaMajorVersion(String version) {
  final match = RegExp(r'^(\d+)(?:\.(\d+))?').firstMatch(version.trim());
  if (match == null) return null;
  final first = int.parse(match.group(1)!);
  if (first != 1) return first;
  final second = match.group(2);
  return second == null ? null : int.parse(second);
}

/// Pulls the version out of `java -version` output.
///
/// The line is on stderr and reads `openjdk version "17.0.11" 2024-04-16`.
String? parseJavaVersionOutput(String output) {
  final quoted = RegExp(r'version\s+"([^"]+)"').firstMatch(output);
  if (quoted != null) return quoted.group(1);
  // Some builds print it unquoted.
  final bare = RegExp(r'version\s+([\w.\-+]+)').firstMatch(output);
  return bare?.group(1);
}

/// Pulls `JavaHome` values out of `reg query … /s /v JavaHome` output.
List<String> parseRegistryJavaHomes(String output) {
  final homes = <String>[];
  final pattern = RegExp(r'JavaHome\s+REG_[A-Z_]+\s+(.+)$');
  for (final line in output.split('\n')) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final value = match.group(1)!.trim();
    if (value.isNotEmpty) homes.add(value);
  }
  return homes;
}

/// Pulls a single `REG_SZ` value out of `reg query … /v <name>` output.
String? parseRegistryValue(String output, String name) {
  final pattern = RegExp('$name\\s+REG_[A-Z_]+\\s+(.+)\$');
  for (final line in output.split('\n')) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final value = match.group(1)!.trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// Reads `jdk-dir` out of `flutter config --list`.
///
/// Unset settings are printed as `(Not set)`, which is not a path.
String? parseFlutterJdkDir(String output) {
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('jdk-dir:')) continue;
    final value = trimmed.substring('jdk-dir:'.length).trim();
    if (value.isEmpty || value.startsWith('(')) return null;
    return value;
  }
  return null;
}
