import 'package:injectable/injectable.dart';

import '../../application/toolchain_events.dart';
import '../../domain/entities/jdk.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../settings/settings_service.dart';
import 'jdk_detection_service.dart';

/// The one place that answers "which JDK is this machine actually using".
///
/// Both the Java page and the Dashboard's toolchain row need that answer, and
/// they used to work it out separately: the Java page scanned every install
/// location through [JdkDetectionService] and applied [resolveActiveJdk], while
/// the Dashboard ran its own `java -version` against `JAVA_HOME` and PATH. A
/// JDK this app downloaded is in neither of those, so it showed as installed on
/// one screen and missing on the other.
///
/// Everything expensive is cached here rather than in the callers, because the
/// callers have different lifetimes — the Dashboard cubit is rebuilt on every
/// visit and must not pay for `flutter config --list` each time. [invalidate]
/// clears the cache and announces it on [ToolchainEvents], which is what makes
/// an install on one screen show up on the other.
@lazySingleton
class JavaToolchainService {
  JavaToolchainService(
    this._detection,
    this._flutter,
    this._settings,
    this._events,
  );

  final JdkDetectionService _detection;
  final FlutterRepository _flutter;
  final SettingsService _settings;
  final ToolchainEvents _events;

  /// `flutter config --jdk-dir`, once read. Cached separately from the fact of
  /// having read it: null is a real answer ("Flutter was never told"), and
  /// re-running a one-second process to learn it again is not free.
  String? _flutterJdkDir;
  bool _readFlutterJdkDir = false;

  /// What `JAVA_HOME` was set to *by this app*, this session.
  ///
  /// Writing a user-level environment variable does not change the variables
  /// this process was started with, so [JdkDetectionService.javaHome] keeps
  /// reporting the old value until a restart. Remembering the write is what
  /// makes both screens agree with what the user just did.
  String? _javaHomeOverride;

  /// Every JDK on the machine, including the ones this app installed and the
  /// ones the user pointed at by hand.
  Future<List<Jdk>> jdks({bool force = false}) => _detection.detect(
    manualPaths: _settings.settings.manualJdkPaths,
    force: force,
  );

  /// Where Flutter was told to look for a JDK, or null when it was not told.
  Future<String?> flutterJdkDir({bool force = false}) async {
    if (_readFlutterJdkDir && !force) return _flutterJdkDir;
    _flutterJdkDir = await _flutter.configuredJdkDir();
    _readFlutterJdkDir = true;
    return _flutterJdkDir;
  }

  /// `JAVA_HOME` — what this app last wrote, or what the process inherited.
  String? get javaHome => _javaHomeOverride ?? _detection.javaHome;

  /// Remembers a `JAVA_HOME` this app just persisted, and announces it.
  set javaHomeOverride(String? path) {
    _javaHomeOverride = path;
    _events.emitChanged();
  }

  /// The JDK root owning the first `java` on PATH.
  Future<String?> pathJdkHome() => _detection.pathJdkHome();

  /// The JDK a build will actually use, and what decided that — or null when
  /// nothing on this machine is pointed at a JDK.
  ///
  /// Priority is [resolveActiveJdk]'s: `flutter config` first (a JDK this app
  /// installed and activated is found here), then `JAVA_HOME`, then PATH.
  ///
  /// The three lookups start together. `flutter config --list` is a process and
  /// the slowest of them by an order of magnitude, so running it alongside the
  /// scan costs the difference rather than the sum.
  Future<ActiveJdk?> active({bool force = false}) async {
    final jdksFuture = jdks(force: force);
    final dirFuture = flutterJdkDir(force: force);
    final pathFuture = pathJdkHome();

    final list = await jdksFuture;
    final dir = await dirFuture;
    final onPath = await pathFuture;

    return resolveActiveJdk(
      list,
      flutterJdkDir: dir,
      javaHome: javaHome,
      pathJdk: onPath,
    );
  }

  /// Re-reads which JDK Flutter was told to use, and announces the change.
  ///
  /// For activation: the set of installed JDKs did not change, only which one is
  /// in force, so the scan cache is deliberately left alone — a rescan here
  /// would cost a second of process spawns to learn nothing.
  Future<String?> refreshActiveJdk() async {
    final dir = await flutterJdkDir(force: true);
    _events.emitChanged();
    return dir;
  }

  /// Drops every cached answer and tells the rest of the app to re-read.
  ///
  /// For an install or a removal: the set of JDKs itself changed, which is what
  /// makes the cached scan a lie.
  void invalidate() {
    _detection.refresh();
    _flutterJdkDir = null;
    _readFlutterJdkDir = false;
    _events.emitChanged();
  }
}
