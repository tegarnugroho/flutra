import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../core/platform/platform_service.dart';
import '../../domain/entities/windows_toolchain.dart';
import '../../domain/repositories/flutter_repository.dart';

/// What an installer run is doing, for the progress line.
enum WindowsSetupStage {
  downloading,

  /// Handed to Windows; the UAC prompt is up.
  launching,

  /// Microsoft's installer is running in its own window.
  installing,
  done,

  /// Succeeded, but Windows wants a restart before the toolchain is whole.
  restartRequired,
  failed;

  String get label => switch (this) {
    WindowsSetupStage.downloading => 'Downloading installer…',
    WindowsSetupStage.launching => 'Waiting for permission…',
    WindowsSetupStage.installing => 'Installing via VS Installer…',
    WindowsSetupStage.done => 'Finished',
    WindowsSetupStage.restartRequired => 'Finished — restart recommended',
    WindowsSetupStage.failed => 'Failed',
  };

  bool get isTerminal =>
      this == done || this == restartRequired || this == failed;
}

/// One step of an installer run.
class WindowsSetupEvent {
  const WindowsSetupEvent({required this.stage, this.progress, this.error});

  final WindowsSetupStage stage;

  /// 0–1 while the bootstrapper downloads. The install itself reports nothing
  /// back — see the class doc.
  final double? progress;

  final String? error;
}

/// Finds and repairs the toolchain a Flutter Windows build needs.
///
/// Detection is unelevated and complete: `vswhere` for the compiler, the
/// registry for the SDK and Developer Mode, `flutter config` for the target.
///
/// Repair is not Flutra's work to do. Every install, modify and update goes
/// through Microsoft's own installer with the documented arguments — this
/// never extracts components by hand and never writes a registry key to fake
/// an install. What it does own is the invocation, the wait, and the re-check.
@lazySingleton
class WindowsToolchainService {
  WindowsToolchainService(this._runner, this._platform, this._flutter);

  final CommandRunner _runner;
  final PlatformService _platform;
  final FlutterRepository _flutter;

  static final Logger _log = Logger('WindowsToolchainService');

  /// `vswhere` and `setup.exe` live at a fixed path that does not move between
  /// Visual Studio versions.
  static String get _installerDir => p.join(
    Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
    'Microsoft Visual Studio',
    'Installer',
  );

  static String get vsWherePath => p.join(_installerDir, 'vswhere.exe');
  static String get vsSetupPath => p.join(_installerDir, 'setup.exe');

  WindowsToolchain? _cache;

  void refresh() => _cache = null;

  /// Reads the machine's toolchain.
  ///
  /// Every step is independent: a failure to read one thing leaves that one
  /// unknown rather than emptying the page.
  Future<WindowsToolchain> detect({bool force = false}) async {
    if (_cache != null && !force) return _cache!;
    if (!_platform.isWindows) return const WindowsToolchain();

    final installs = await _visualStudioInstalls();
    final sdks = await _windowsSdks();
    final developerMode = await _developerMode();
    final windowsDesktop = await _windowsDesktopEnabled();

    return _cache = WindowsToolchain(
      installs: installs,
      sdks: sdks,
      developerMode: developerMode,
      windowsDesktopEnabled: windowsDesktop,
    );
  }

  // ---- 1a. Visual Studio ---------------------------------------------------

  Future<List<VisualStudioInstall>> _visualStudioInstalls() async {
    if (!File(vsWherePath).existsSync()) return const [];

    // Two calls. The JSON carries no component list, so the second asks which
    // installs have the MSVC toolset and the paths are matched up — that is
    // also how an install *missing* the workload stays visible.
    final all = await _vsWhere([
      '-products',
      '*',
      '-prerelease',
      '-format',
      'json',
      '-utf8',
    ]);
    if (all == null) return const [];

    final withCpp = await _vsWhere([
      '-products',
      '*',
      '-prerelease',
      '-requires',
      kVcToolsComponent,
      '-property',
      'installationPath',
    ]);

    return parseVsWhere(
      all,
      withCppTools:
          withCpp == null ? const {} : parseVsWherePaths(withCpp).toSet(),
    );
  }

  Future<String?> _vsWhere(List<String> arguments) async {
    try {
      final result = await _runner.run(
        vsWherePath,
        arguments,
        timeout: const Duration(seconds: 30),
      );
      return result.isSuccess ? result.stdout : null;
    } catch (e) {
      _log.fine('vswhere failed: $e');
      return null;
    }
  }

  // ---- 1b. Windows SDK -----------------------------------------------------

  /// The SDK root, from either registry key Microsoft has used for it, then
  /// the version folders under it.
  Future<List<WindowsSdk>> _windowsSdks() async {
    for (final (key, value) in const [
      (
        r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Microsoft SDKs\Windows\v10.0',
        'InstallationFolder',
      ),
      // Older layouts only have the kits key; both point at the same tree.
      (r'HKLM\SOFTWARE\Microsoft\Windows Kits\Installed Roots', 'KitsRoot10'),
    ]) {
      final root = await _registryValue(key, value);
      if (root == null) continue;
      final include = Directory(p.join(root, 'Include'));
      if (!include.existsSync()) continue;
      try {
        return parseSdkVersions(
          include.listSync().whereType<Directory>().map(
            (d) => p.basename(d.path),
          ),
          kitRoot: root,
        );
      } catch (e) {
        _log.fine('could not list $include: $e');
      }
    }
    return const [];
  }

  // ---- 1c. Developer Mode --------------------------------------------------

  /// Read-only, always. The key lives in HKLM and writing it needs admin —
  /// which is why the tile sends people to Settings instead.
  Future<DeveloperModeState> _developerMode() async {
    final output = await _registryQuery(
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock',
      'AllowDevelopmentWithoutDevLicense',
    );
    return output == null
        ? DeveloperModeState.unknown
        : parseDeveloperMode(output);
  }

  // ---- 1d. Flutter config --------------------------------------------------

  Future<bool?> _windowsDesktopEnabled() async {
    try {
      return await _flutter.isWindowsDesktopEnabled();
    } on Failure {
      return null;
    }
  }

  /// Turns the Windows desktop target on, then clears the cache so the next
  /// detect sees it.
  Future<void> enableWindowsDesktop() async {
    await _flutter.setWindowsDesktopEnabled(true);
    refresh();
  }

  /// Opens the Settings page that owns Developer Mode.
  Future<void> openDeveloperModeSettings() async {
    try {
      await _runner.run(
        'cmd',
        ['/c', 'start', '', kDeveloperModeSettingsUri],
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      _log.warning('could not open $kDeveloperModeSettingsUri: $e');
    }
  }

  // ---- registry helpers ----------------------------------------------------

  Future<String?> _registryQuery(String key, String value) async {
    try {
      final result = await _runner.run(
        'reg',
        ['query', key, '/v', value],
        timeout: const Duration(seconds: 15),
      );
      return result.isSuccess ? result.stdout : null;
    } catch (e) {
      _log.fine('reg query $key failed: $e');
      return null;
    }
  }

  Future<String?> _registryValue(String key, String value) async {
    final output = await _registryQuery(key, value);
    return output == null ? null : parseRegistryValue(output, value);
  }

  // ---- 3. Install / modify / update ----------------------------------------

  /// Installs Build Tools with the C++ workload, from nothing.
  Stream<WindowsSetupEvent> installBuildTools() async* {
    try {
      final bootstrapper = await _bootstrapper();
      yield* _runInstaller(bootstrapper.path, [
        '--add',
        kBuildToolsWorkload,
        '--includeRecommended',
      ]);
    } on Failure catch (e) {
      yield WindowsSetupEvent(
        stage: WindowsSetupStage.failed,
        error: e.message,
      );
    } catch (e) {
      yield WindowsSetupEvent(stage: WindowsSetupStage.failed, error: '$e');
    }
  }

  /// Adds the C++ workload to an install that has everything else.
  Stream<WindowsSetupEvent> addCppWorkload(VisualStudioInstall install) =>
      _modify(install, ['--add', install.cppWorkload, '--includeRecommended']);

  /// Adds the Windows SDK component to an existing install.
  Stream<WindowsSetupEvent> addWindowsSdk(VisualStudioInstall install) =>
      _modify(install, ['--add', kWindowsSdkComponent]);

  /// Finishes an install that was interrupted.
  Stream<WindowsSetupEvent> repair(VisualStudioInstall install) =>
      _setup(['repair', '--installPath', install.installPath]);

  /// Updates an install to the newest build Microsoft ships.
  Stream<WindowsSetupEvent> update(VisualStudioInstall install) =>
      _setup(['update', '--installPath', install.installPath]);

  Stream<WindowsSetupEvent> _modify(
    VisualStudioInstall install,
    List<String> components,
  ) => _setup([
    'modify',
    '--installPath',
    install.installPath,
    ...components,
  ]);

  Stream<WindowsSetupEvent> _setup(List<String> arguments) async* {
    if (!File(vsSetupPath).existsSync()) {
      yield const WindowsSetupEvent(
        stage: WindowsSetupStage.failed,
        error: 'The Visual Studio Installer is not on this machine.',
      );
      return;
    }
    yield* _runInstaller(vsSetupPath, arguments);
  }

  /// The one place an installer is launched, waited on and read.
  ///
  /// `--passive` and never `--quiet`: quiet hides Microsoft's licence
  /// acceptance and its own elevation prompt, both of which the user is
  /// entitled to see. `--norestart` because deciding to reboot is theirs too.
  Stream<WindowsSetupEvent> _runInstaller(
    String executable,
    List<String> arguments,
  ) async* {
    yield const WindowsSetupEvent(stage: WindowsSetupStage.launching);

    final all = [...arguments, '--passive', '--norestart', '--wait'];
    yield const WindowsSetupEvent(stage: WindowsSetupStage.installing);

    final CommandResultLike result;
    try {
      final run = await _runner.run(
        executable,
        all,
        // Installing the C++ workload pulls gigabytes; slow on any line.
        timeout: const Duration(hours: 2),
      );
      result = (exitCode: run.exitCode, output: run.combinedOutput);
    } catch (e) {
      yield WindowsSetupEvent(stage: WindowsSetupStage.failed, error: '$e');
      return;
    }

    // The installer's own exit codes: 0 done, 3010 done-but-reboot, 1602
    // cancelled, 1223 the UAC prompt was declined.
    switch (result.exitCode) {
      case 0:
        yield const WindowsSetupEvent(stage: WindowsSetupStage.done);
      case 3010:
        yield const WindowsSetupEvent(
          stage: WindowsSetupStage.restartRequired,
        );
      case 1602 || 1223:
        yield const WindowsSetupEvent(
          stage: WindowsSetupStage.failed,
          error: 'The installer was cancelled.',
        );
      default:
        _log.warning('installer exited ${result.exitCode}: ${result.output}');
        yield WindowsSetupEvent(
          stage: WindowsSetupStage.failed,
          error: 'The installer exited with code ${result.exitCode}.',
        );
    }
  }

  /// The cached bootstrapper, downloaded only when it is not already there.
  ///
  /// A stub that fails its signature check is not one to run: it is deleted
  /// and fetched again.
  Future<File> _bootstrapper() async {
    final support = await getApplicationSupportDirectory();
    final target = File(p.join(support.path, 'vs_BuildTools.exe'));

    if (target.existsSync() && await _isSigned(target)) return target;
    if (target.existsSync()) {
      _log.warning('cached bootstrapper failed its signature check');
      try {
        target.deleteSync();
      } catch (_) {}
    }

    await Dio().download(kBuildToolsBootstrapperUrl, target.path);
    if (!await _isSigned(target)) {
      try {
        target.deleteSync();
      } catch (_) {}
      throw const NetworkFailure(
        'The downloaded installer failed its signature check.',
        suggestion: 'Try again, or download Build Tools from microsoft.com.',
      );
    }
    return target;
  }

  Future<bool> _isSigned(File file) async {
    try {
      final result = await _runner.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '(Get-AuthenticodeSignature -LiteralPath '
              "'${file.path.replaceAll("'", "''")}').Status",
        ],
        timeout: const Duration(seconds: 30),
      );
      return result.isSuccess && result.stdout.trim() == 'Valid';
    } catch (e) {
      _log.fine('signature check failed: $e');
      return false;
    }
  }
}

/// Just the two fields the exit-code switch reads.
typedef CommandResultLike = ({int exitCode, String output});
