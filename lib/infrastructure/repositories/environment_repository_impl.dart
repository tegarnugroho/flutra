import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../core/platform/platform_service.dart';
import '../../domain/entities/environment_snapshot.dart';
import '../../domain/entities/jdk.dart';
import '../../domain/entities/tool_status.dart';
import '../../domain/repositories/environment_repository.dart';
import '../flutter/flutter_update_service.dart';
import '../java/java_toolchain_service.dart';
import '../sdk/sdk_locator.dart';

/// The Dashboard's Java row for the JDK a build will actually use.
///
/// Pure, so the mapping the row depends on — green with a version for a usable
/// JDK, and where the row says it came from — is testable without a machine that
/// has one installed.
///
/// A JRE reads as an error rather than as installed: it will not compile
/// anything, and reporting the toolchain as ready when a Gradle build is going
/// to fail is the more expensive kind of wrong.
ToolStatus javaStatusOf(ActiveJdk active) {
  final jdk = active.jdk;
  return ToolStatus(
    kind: ToolKind.java,
    state: jdk.isSelectable ? ToolState.installed : ToolState.error,
    version: jdk.version,
    path: jdk.path,
    detail: jdk.isSelectable
        ? '${jdk.source.label} • via ${active.source.label}'
        : 'No compiler here — this is a JRE, not a JDK.',
  );
}

/// Concrete [EnvironmentRepository] that probes the real toolchain.
///
/// Each tool is detected independently and concurrently; a failure in one probe
/// never aborts the others — it surfaces as an error/missing [ToolStatus].
@LazySingleton(as: EnvironmentRepository)
class EnvironmentRepositoryImpl implements EnvironmentRepository {
  EnvironmentRepositoryImpl(
    this._runner,
    this._locator,
    this._flutterUpdates,
    this._platform,
    this._java,
  );

  final CommandRunner _runner;
  final SdkLocator _locator;
  final PlatformService _platform;
  final FlutterUpdateService _flutterUpdates;
  final JavaToolchainService _java;

  static const _probeTimeout = Duration(seconds: 30);

  static final Logger _log = Logger('EnvironmentRepository');

  @override
  Future<EnvironmentSnapshot> detect({bool forceRefresh = false}) async {
    // Two waves, not five probes at once.
    //
    // Each probe is one or two `Process.start` calls (the version check, plus a
    // `where` lookup for the tool's path), and on Windows every spawn blocks
    // the calling isolate for ~1.2ms. All of them together stalls the event
    // loop long enough to drop frames on the Dashboard while its skeleton is
    // animating; measured lag scales with how many are in flight — 3 at once
    // costs ~10ms, 9 at once costs 32-75ms.
    //
    // Flutter leads: it is the slowest (~600ms) and the only one that may hit
    // the network, so starting it first overlaps it with the rest.
    final first = await Future.wait([
      _detectFlutter(forceRefresh: forceRefresh),
      _detectSdk(), // pure filesystem, spawns nothing
      _detectAdb(),
    ]);
    // Java sits in the second wave because it is the heavier of the two now: it
    // resolves the active JDK, which reads `flutter config --list` once per app
    // run and caches it. Paired with the emulator probe rather than added to the
    // first wave so no wave grows past three spawns in flight.
    final second = await Future.wait([
      _detectJava(),
      _detectEmulator(),
    ]);

    final flutter = first[0];
    final sdk = first[1];
    final adb = first[2];
    final java = second[0];
    final emulator = second[1];

    return EnvironmentSnapshot(
      sdk: sdk,
      java: java,
      flutter: flutter,
      emulator: emulator,
      adb: adb,
      sdkPath: _locator.sdkRoot,
      javaPath: java.path,
      flutterPath: flutter.path,
      platformToolsVersion: adb.version,
      buildToolsVersion: _locator.latestBuildToolsVersion,
      emulatorVersion: emulator.version,
    );
  }

  // ---- Android SDK ---------------------------------------------------------

  Future<ToolStatus> _detectSdk() async {
    final root = _locator.sdkRoot;
    if (root == null) {
      return const ToolStatus(
        kind: ToolKind.sdk,
        state: ToolState.missing,
        detail: 'No SDK detected. Set one up on the SDK manager page.',
      );
    }

    final platforms = _locator.installedPlatforms;
    final buildTools = _locator.installedBuildToolsVersions;
    final parts = <String>[
      '${platforms.length} platform(s)',
      '${buildTools.length} build-tools',
    ];

    return ToolStatus(
      kind: ToolKind.sdk,
      state: ToolState.installed,
      path: root,
      detail: parts.join(' • '),
    );
  }

  // ---- Java ----------------------------------------------------------------

  /// The JDK row, from the same registry the Java page lists.
  ///
  /// [JavaToolchainService] is asked first because it knows about the JDKs this
  /// app installed into its own folder — which is where a Flutra-managed JDK
  /// lives, and it is on neither `JAVA_HOME` nor PATH. Probing the environment
  /// was all this did before, so a managed JDK that the Java page showed as
  /// active still read "not detected" here.
  ///
  /// The environment probe below is kept as the fallback: the scan can come back
  /// with nothing on a machine where `java` still answers (a JDK reached through
  /// a wrapper script, a container image with no recognisable layout), and this
  /// row must not become *less* able to find one than it was.
  Future<ToolStatus> _detectJava() async {
    try {
      final active = await _java.active();
      if (active != null) return javaStatusOf(active);
    } catch (e) {
      // A scan that fell over is not the end of the row: the probe below is
      // still worth trying, and it is what used to answer this on its own.
      _log.fine('JDK registry lookup failed, falling back to a probe: $e');
    }
    return _probeJava();
  }

  /// `java -version` against `JAVA_HOME`, or whatever PATH resolves.
  Future<ToolStatus> _probeJava() async {
    final javaHome = Platform.environment['JAVA_HOME'];
    final executable = javaHome != null
        ? p.join(javaHome, 'bin', _platform.executableName('java'))
        : 'java';

    try {
      // `java -version` prints to stderr on virtually all JDKs.
      final result = await _runner.run(
        executable,
        ['-version'],
        timeout: _probeTimeout,
      );
      final output = result.combinedOutput;
      final version = _firstMatch(output, RegExp(r'version "([^"]+)"')) ??
          _firstMatch(output, RegExp(r'(\d+\.\d+\.\d+)'));
      return ToolStatus(
        kind: ToolKind.java,
        state: version == null ? ToolState.error : ToolState.installed,
        version: version,
        path: javaHome ?? await _runner.which('java'),
      );
    } on ExecutableNotFoundFailure {
      return const ToolStatus(
        kind: ToolKind.java,
        state: ToolState.missing,
        detail: 'Java (JDK 17+) is required by the Android tools.',
      );
    } on Failure catch (e) {
      return _errorStatus(ToolKind.java, e);
    }
  }

  // ---- Flutter -------------------------------------------------------------

  Future<ToolStatus> _detectFlutter({bool forceRefresh = false}) async {
    try {
      final result = await _runner.run(
        _platform.flutterExecutable,
        ['--version', '--machine'],
        timeout: _probeTimeout,
      );
      // Prefer the human line for a friendly version; fall back to raw.
      final version = _firstMatch(
        result.combinedOutput,
        RegExp(r'"frameworkVersion"\s*:\s*"([^"]+)"'),
      );
      final channel = _firstMatch(
        result.combinedOutput,
        RegExp(r'"channel"\s*:\s*"([^"]+)"'),
      );
      final path = await _runner.which('flutter');
      if (!result.isSuccess) {
        return ToolStatus(
          kind: ToolKind.flutter,
          state: ToolState.error,
          version: version,
          path: path,
        );
      }
      // Compare the checkout's HEAD with the channel's published tip; version
      // strings can't see hotfix re-releases.
      final update = channel == null
          ? null
          : await _flutterUpdates.check(
              channel: channel, forceRefresh: forceRefresh);
      final outdated = update?.updateAvailable ?? false;
      return ToolStatus(
        kind: ToolKind.flutter,
        state: outdated ? ToolState.needsUpdate : ToolState.installed,
        version: version,
        path: path,
        detail: outdated
            ? 'update available: ${update!.latest!.displayVersion}'
            : null,
        latestVersion: outdated ? update!.latest!.displayVersion : null,
      );
    } on ExecutableNotFoundFailure {
      return const ToolStatus(
        kind: ToolKind.flutter,
        state: ToolState.missing,
        detail: 'Flutter is not on your PATH.',
      );
    } on Failure catch (e) {
      return _errorStatus(ToolKind.flutter, e);
    }
  }

  // ---- Emulator ------------------------------------------------------------

  Future<ToolStatus> _detectEmulator() async {
    final exe = _locator.emulator;
    if (exe == null) {
      return const ToolStatus(
        kind: ToolKind.emulator,
        state: ToolState.missing,
        detail: 'Install the "emulator" package from the SDK Manager.',
      );
    }
    try {
      final result = await _runner.run(exe, ['-version'],
          timeout: _probeTimeout);
      final version = _firstMatch(
        result.combinedOutput,
        RegExp(r'version\s+([\d.]+)', caseSensitive: false),
      );
      return ToolStatus(
        kind: ToolKind.emulator,
        state: ToolState.installed,
        version: version,
        path: exe,
      );
    } on Failure catch (e) {
      return _errorStatus(ToolKind.emulator, e);
    }
  }

  // ---- ADB / platform-tools ------------------------------------------------

  Future<ToolStatus> _detectAdb() async {
    final exe = _locator.adb;
    if (exe == null) {
      return const ToolStatus(
        kind: ToolKind.adb,
        state: ToolState.missing,
        detail: 'Install "platform-tools" from the SDK Manager.',
      );
    }
    try {
      final result = await _runner.run(exe, ['--version'],
          timeout: _probeTimeout);
      final version = _firstMatch(
        result.combinedOutput,
        RegExp(r'version\s+([\d.]+)', caseSensitive: false),
      );
      return ToolStatus(
        kind: ToolKind.adb,
        state: ToolState.installed,
        version: version,
        path: exe,
      );
    } on Failure catch (e) {
      return _errorStatus(ToolKind.adb, e);
    }
  }

  // ---- Helpers -------------------------------------------------------------

  ToolStatus _errorStatus(ToolKind kind, Failure failure) => ToolStatus(
        kind: kind,
        state: ToolState.error,
        detail: failure.message,
      );

  String? _firstMatch(String input, RegExp pattern) {
    final match = pattern.firstMatch(input);
    return match?.group(1);
  }
}
