import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../core/platform/platform_service.dart';
import '../../domain/entities/jdk.dart';

/// Finds every JDK on the machine, and what each one is.
///
/// The environment only knows about the JDK someone wired into it; installers,
/// Android Studio and IntelliJ each drop JDKs somewhere else entirely. This
/// looks in all of those places, so the page can answer "which one is my build
/// actually using" against the full set rather than the one on PATH.
@lazySingleton
class JdkDetectionService {
  JdkDetectionService(this._runner, this._platform);

  final CommandRunner _runner;
  final PlatformService _platform;

  static final Logger _log = Logger('JdkDetectionService');

  /// A JDK that will not answer `java -version` in this long is not one worth
  /// waiting on — the list has to arrive.
  static const _probeTimeout = Duration(seconds: 3);

  List<Jdk>? _cache;

  /// Every JDK found, best-known first, deduped by resolved path.
  ///
  /// Cached until [refresh]; [manualPaths] are folded in on every call so
  /// adding one does not force a full rescan.
  Future<List<Jdk>> detect({
    List<String> manualPaths = const [],
    bool force = false,
  }) async {
    if (_cache != null && !force) {
      return _merge(_cache!, await _describeAll(manualPaths, JdkSource.manual));
    }
    final found = await _scan();
    _cache = found;
    return _merge(found, await _describeAll(manualPaths, JdkSource.manual));
  }

  void refresh() => _cache = null;

  /// `JAVA_HOME`, if it is set to something.
  String? get javaHome {
    final value = Platform.environment['JAVA_HOME']?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// The JDK root owning the first `java` on PATH, or null when there is none.
  Future<String?> pathJdkHome() async {
    final executable = await _runner.which(_platform.executableName('java'));
    return executable == null ? null : jdkHomeOf(executable);
  }

  /// `…\jdk-17\bin\java.exe` → `…\jdk-17`.
  static String? jdkHomeOf(String executable) {
    final bin = p.dirname(executable);
    if (p.basename(bin).toLowerCase() != 'bin') return null;
    return p.dirname(bin);
  }

  /// Whether [directory] looks like a JDK or JRE root at all.
  bool looksLikeJavaHome(String directory) =>
      File(p.join(directory, 'bin', _platform.executableName('java')))
          .existsSync();

  /// Reads one directory as a JDK, whatever state it is in.
  ///
  /// Returns null only when there is no `java` there at all — everything else
  /// comes back as an entry, because a JDK the app cannot read is still one the
  /// user can see in Explorer and wonder about.
  Future<Jdk?> describe(String directory, JdkSource source) async {
    final root = _resolve(directory);
    if (!looksLikeJavaHome(root)) return null;

    final hasCompiler =
        File(p.join(root, 'bin', _platform.executableName('javac')))
            .existsSync();

    final release = await _readRelease(root);
    var version = release?['JAVA_VERSION'];
    final vendor = release?['IMPLEMENTOR'];
    final arch = release?['OS_ARCH'];

    // No release file (or an unreadable one) is normal for repackaged JDKs;
    // asking the binary itself is the fallback, and it is why this is async.
    version ??= await _probeVersion(root);

    final validity = version == null
        ? JdkValidity.invalid
        : hasCompiler
        ? JdkValidity.valid
        : JdkValidity.jreOnly;

    return Jdk(
      path: root,
      source: source,
      validity: validity,
      version: version,
      vendor: vendor,
      arch: arch,
    );
  }

  // ---- discovery -----------------------------------------------------------

  Future<List<Jdk>> _scan() async {
    final found = <Jdk>[];

    // Ordered by how much each source knows about the install: a registry
    // entry names a real installer, PATH only names what a shell happened to
    // export. The first source to claim a path is the one the tile shows.
    found.addAll(await _describeAll(await _registryHomes(), JdkSource.registry));
    found.addAll(await _describeAll(_commonDirJdks(), JdkSource.disk));
    found.addAll(await _describeAll(_jdksDirJdks(), JdkSource.jdksDir));
    found.addAll(
      await _describeAll(await _androidStudioJbr(), JdkSource.androidStudio),
    );
    final home = javaHome;
    if (home != null) {
      found.addAll(await _describeAll([home], JdkSource.javaHome));
    }
    final onPath = await pathJdkHome();
    if (onPath != null) {
      found.addAll(await _describeAll([onPath], JdkSource.path));
    }

    return _dedupe(found);
  }

  Future<List<Jdk>> _describeAll(
    List<String> directories,
    JdkSource source,
  ) async {
    final out = <Jdk>[];
    for (final directory in directories) {
      try {
        final jdk = await describe(directory, source);
        if (jdk != null) out.add(jdk);
      } catch (e) {
        _log.fine('could not read $directory: $e');
      }
    }
    return out;
  }

  /// `HKLM\SOFTWARE\JavaSoft\JDK` and the legacy key beside it.
  Future<List<String>> _registryHomes() async {
    if (!_platform.isWindows) return const [];
    const keys = [
      r'HKLM\SOFTWARE\JavaSoft\JDK',
      r'HKLM\SOFTWARE\JavaSoft\Java Development Kit',
    ];
    final homes = <String>[];
    for (final key in keys) {
      final output = await _reg([key, '/s', '/v', 'JavaHome']);
      if (output != null) homes.addAll(parseRegistryJavaHomes(output));
    }
    return homes;
  }

  /// Every immediate child of the platform's JDK folders.
  List<String> _commonDirJdks() {
    final out = <String>[];
    for (final root in _platform.jdkSearchPaths) {
      out.addAll(_childDirectories(root));
    }
    return out;
  }

  /// `%USERPROFILE%\.jdks` — IntelliJ and Android Studio downloads.
  List<String> _jdksDirJdks() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];
    return _childDirectories(p.join(home, '.jdks'));
  }

  /// The JBR shipped inside Android Studio.
  ///
  /// Missing Android Studio is not an error — most machines that build Flutter
  /// have one, plenty do not.
  Future<List<String>> _androidStudioJbr() async {
    final roots = <String>[];
    if (_platform.isWindows) {
      final fromRegistry = await _reg([
        r'HKLM\SOFTWARE\Android Studio',
        '/v',
        'Path',
      ]);
      final path = fromRegistry == null
          ? null
          : parseRegistryValue(fromRegistry, 'Path');
      if (path != null) roots.add(path);

      final programFiles =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final localAppData = Platform.environment['LOCALAPPDATA'];
      roots.add(p.join(programFiles, 'Android', 'Android Studio'));
      if (localAppData != null) {
        roots.add(p.join(localAppData, 'Programs', 'Android Studio'));
      }
    }
    return [
      for (final root in roots)
        if (Directory(p.join(root, 'jbr')).existsSync()) p.join(root, 'jbr'),
    ];
  }

  List<String> _childDirectories(String root) {
    final directory = Directory(root);
    if (!directory.existsSync()) return const [];
    try {
      return [
        for (final child in directory.listSync().whereType<Directory>())
          child.path,
      ];
    } catch (e) {
      // An unreadable folder (permissions, a disconnected drive) holds nothing
      // as far as this scan is concerned.
      _log.fine('could not list $root: $e');
      return const [];
    }
  }

  /// Runs `reg query`, returning null when the key is absent — which is the
  /// normal answer on a machine without that vendor's installer.
  Future<String?> _reg(List<String> arguments) async {
    try {
      final result = await _runner.run(
        'reg',
        ['query', ...arguments],
        timeout: const Duration(seconds: 10),
      );
      return result.isSuccess ? result.stdout : null;
    } on Failure catch (e) {
      _log.fine('reg query failed: ${e.message}');
      return null;
    } catch (e) {
      _log.fine('reg query failed: $e');
      return null;
    }
  }

  // ---- per-JDK metadata ----------------------------------------------------

  Future<Map<String, String>?> _readRelease(String root) async {
    final file = File(p.join(root, 'release'));
    if (!file.existsSync()) return null;
    try {
      final values = parseReleaseFile(await file.readAsString());
      return values.isEmpty ? null : values;
    } catch (e) {
      _log.fine('could not read $file: $e');
      return null;
    }
  }

  Future<String?> _probeVersion(String root) async {
    final executable = p.join(root, 'bin', _platform.executableName('java'));
    try {
      final result = await _runner.run(
        executable,
        ['-version'],
        timeout: _probeTimeout,
      );
      // `java -version` writes to stderr; some builds use stdout.
      return parseJavaVersionOutput(result.combinedOutput);
    } on Failure catch (e) {
      _log.fine('$executable -version failed: ${e.message}');
      return null;
    } catch (e) {
      _log.fine('$executable -version failed: $e');
      return null;
    }
  }

  /// Follows symlinks and junctions so the same JDK reached two ways dedupes.
  String _resolve(String directory) {
    try {
      return Directory(directory).resolveSymbolicLinksSync();
    } catch (_) {
      return p.normalize(directory);
    }
  }

  /// Keeps the first entry per path, which is the highest-priority source.
  static List<Jdk> _dedupe(List<Jdk> jdks) {
    final seen = <String>{};
    final out = <Jdk>[];
    for (final jdk in jdks) {
      if (!seen.add(jdk.path.toLowerCase())) continue;
      out.add(jdk);
    }
    return out;
  }

  /// Folds manual entries into a scan result, ahead of what was found on disk
  /// so a hand-picked JDK keeps its badge.
  static List<Jdk> _merge(List<Jdk> scanned, List<Jdk> manual) =>
      _dedupe([...manual, ...scanned]);
}
