import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../application/toolchain_events.dart';
import '../../core/command/command_result.dart';
import '../../core/command/command_runner.dart';
import '../java/java_toolchain_service.dart';
import '../java/jdk_install_service.dart';

/// The one place that spawns an Android SDK command-line tool.
///
/// `sdkmanager`, `avdmanager` and the licence prompt are shell wrappers around a
/// Java program. With no `java` reachable they exit 1 having printed
///
///     ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.
///
/// to *stdout* — so a caller that treats "non-empty stdout" as a successful run
/// parses an error message into zero packages and shows an empty catalogue.
///
/// The JDK this app downloads lives in its own app-support directory, which is
/// on neither `PATH` nor `JAVA_HOME`. On a machine with no system Java that is
/// every Android tool failing that way immediately after a successful bootstrap:
/// the SDK is there, the JDK is there, and nothing told one about the other.
///
/// Routing every Android-tool spawn through here is what makes "the JDK Flutra
/// manages is the JDK Flutra's tools run on" true once instead of five times —
/// the SDK manager, the licence prompt, virtual devices, Update all and Quick
/// setup all reach the tools through this class.
@lazySingleton
class AndroidToolRunner {
  AndroidToolRunner(
    this._runner,
    JavaToolchainService this._toolchain,
    JdkInstallService this._installs,
    ToolchainEvents events,
  ) {
    // Installing or activating a JDK changes the answer, and the tools must not
    // keep running on the one that was in force when the app started.
    _changes = events.onChanged.listen((_) => invalidate());
  }

  /// A runner that resolves no JDK and spawns with the ambient environment.
  ///
  /// For the parts of these repositories that touch only the filesystem —
  /// renaming an AVD is the whole of one — where wiring up the JDK registry
  /// would be building a toolchain to not use it.
  @visibleForTesting
  AndroidToolRunner.ambient(this._runner)
      : _toolchain = null,
        _installs = null;

  final CommandRunner _runner;
  final JavaToolchainService? _toolchain;
  final JdkInstallService? _installs;

  static final Logger _log = Logger('AndroidToolRunner');

  StreamSubscription<void>? _changes;

  /// The resolved environment, cached for the session. Resolution reads the
  /// disk and may run `flutter config`, and these tools are spawned per package
  /// during an install queue — paying for it once is the point.
  Map<String, String>? _cached;

  /// The `JAVA_HOME` these tools will be given, or null when nothing on this
  /// machine could be found. Exposed for diagnostics and tests.
  Future<String?> javaHome() async => (await _environment())['JAVA_HOME'];

  /// Drops the cached environment, so the next spawn re-resolves the JDK.
  void invalidate() => _cached = null;

  @disposeMethod
  void dispose() => unawaited(_changes?.cancel() ?? Future<void>.value());

  /// Runs an Android tool to completion with the JDK environment applied.
  ///
  /// Mirrors [CommandRunner.run], including that a non-zero exit does not throw.
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Duration? timeout,
    bool runInShell = true,
  }) async =>
      _runner.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: await _environment(),
        timeout: timeout,
        runInShell: runInShell,
      );

  /// Starts an Android tool for streaming with the JDK environment applied.
  ///
  /// Mirrors [CommandRunner.start].
  Future<RunningCommand> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = true,
  }) async =>
      _runner.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: await _environment(),
        runInShell: runInShell,
      );

  // ---- Environment ---------------------------------------------------------

  Future<Map<String, String>> _environment() async {
    final cached = _cached;
    if (cached != null) return cached;

    final home = await _resolveJavaHome();
    if (home == null) {
      _log.warning('no JDK found; Android tools will run on whatever java the '
          'system provides, if any');
      return _cached = const {};
    }

    // JAVA_HOME alone is enough for the sdkmanager/avdmanager wrappers, but not
    // for everything they in turn shell out to, and `emulator` looks for java on
    // PATH rather than reading JAVA_HOME at all.
    final parentPath = Platform.environment[_pathKey] ?? '';
    final bin = p.join(home, 'bin');
    _log.info('Android tools will run on JDK at $home');
    return _cached = {
      'JAVA_HOME': home,
      _pathKey: parentPath.isEmpty ? bin : '$bin$_listSeparator$parentPath',
    };
  }

  /// Which JDK the Android tools should run on.
  Future<String?> _resolveJavaHome() async {
    // 1. Whatever the Java page calls active: `flutter config --jdk-dir`, then
    //    JAVA_HOME, then PATH. A JDK the user activated in this app is the one
    //    their builds use, and its own tools must not disagree with it. A JDK
    //    this app installed and activated is found here.
    try {
      final active = await _toolchain?.active();
      final path = active?.jdk.path;
      if (path != null && isJavaHome(path)) return path;
    } catch (e) {
      // Resolution runs `flutter config`, which is absent or broken on plenty
      // of machines. That is not a reason to spawn nothing.
      _log.fine('could not resolve the active JDK: $e');
    }

    // 2. A JDK this app downloaded but that nothing points at yet. This is the
    //    case immediately after a first-run bootstrap, and the one the empty
    //    package list came from.
    final managed = await _managedJavaHome();
    if (managed != null) return managed;

    // 3. The system's own, taken literally — step 1 only returns it when the
    //    detection scan also recognised it as a JDK, and an unrecognised one
    //    still runs java.
    final env = Platform.environment['JAVA_HOME']?.trim();
    if (env != null && env.isNotEmpty && isJavaHome(env)) return env;

    return null;
  }

  /// The newest Flutra-managed JDK on disk, or null when none was installed.
  ///
  /// Read from the directory rather than from settings because there is no
  /// setting: a managed JDK becomes "the" JDK by being activated, and one that
  /// was never activated is still the only Java this machine has.
  Future<String?> _managedJavaHome() async {
    try {
      final installs = _installs;
      if (installs == null) return null;
      final root = await installs.managedRoot();
      return newestJdkIn(root.listSync().whereType<Directory>().map((d) => d.path));
    } catch (e) {
      _log.fine('could not read the managed JDK directory: $e');
      return null;
    }
  }

  /// The newest of [directories] that actually holds a `java`, or null.
  ///
  /// Static and pure because "which of the two JDKs I have installed do my
  /// tools get" should be answerable without installing two JDKs.
  @visibleForTesting
  static String? newestJdkIn(Iterable<String> directories) {
    // Folder names are `<vendor>-<version>`, so the newest sorts last under a
    // numeric comparison of the version tail. A string sort would put
    // `temurin-9` above `temurin-21`.
    final candidates = directories.where(isJavaHome).toList()
      ..sort(_compareManaged);
    return candidates.isEmpty ? null : candidates.last;
  }

  static int _compareManaged(String a, String b) {
    final va = _versionOf(a);
    final vb = _versionOf(b);
    for (var i = 0; i < va.length && i < vb.length; i++) {
      if (va[i] != vb[i]) return va[i].compareTo(vb[i]);
    }
    if (va.length != vb.length) return va.length.compareTo(vb.length);
    return p.basename(a).compareTo(p.basename(b));
  }

  /// `…/jdks/temurin-17.0.20` → `[17, 0, 20]`.
  static List<int> _versionOf(String path) {
    final name = p.basename(path);
    final dash = name.lastIndexOf('-');
    final tail = dash < 0 ? name : name.substring(dash + 1);
    return tail
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  /// Whether [directory] actually holds a `java` we can run.
  ///
  /// Both spellings are tested on every platform rather than asking
  /// [Platform.isWindows]: the check costs a `stat` either way, and a JDK
  /// unpacked on one OS and read on another is a thing this app can produce.
  @visibleForTesting
  static bool isJavaHome(String directory) =>
      File(p.join(directory, 'bin', 'java')).existsSync() ||
      File(p.join(directory, 'bin', 'java.exe')).existsSync();

  /// The separator between PATH entries — not [Platform.pathSeparator], which
  /// is the one inside a path.
  static String get _listSeparator => Platform.isWindows ? ';' : ':';

  /// The parent environment's own spelling of PATH.
  ///
  /// Windows is case-insensitive about it and usually spells it `Path`; passing
  /// a differently-cased key risks handing the child two of them.
  static String get _pathKey {
    if (!Platform.isWindows) return 'PATH';
    for (final key in Platform.environment.keys) {
      if (key.toUpperCase() == 'PATH') return key;
    }
    return 'Path';
  }
}
