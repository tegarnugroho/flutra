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

/// What the toolchain installer is doing, for the progress line.
enum WindowsSetupStage {
  downloading,
  launching,

  /// The Microsoft installer is running in its own window.
  installing,
  done,
  failed;

  String get label => switch (this) {
    WindowsSetupStage.downloading => 'Downloading installer…',
    WindowsSetupStage.launching => 'Waiting for permission…',
    WindowsSetupStage.installing => 'Installer running…',
    WindowsSetupStage.done => 'Finished',
    WindowsSetupStage.failed => 'Failed',
  };
}

/// One step of a setup run.
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
/// registry for the Windows SDK. Installing is not — every Microsoft installer
/// here requires admin, and an elevated child cannot hand its output back to a
/// process that is not. So a setup run downloads the bootstrapper, asks Windows
/// for elevation, and then waits: Microsoft's installer shows its own progress
/// in its own window, and this re-scans once it exits.
@lazySingleton
class WindowsToolchainService {
  WindowsToolchainService(this._runner, this._platform);

  final CommandRunner _runner;
  final PlatformService _platform;

  static final Logger _log = Logger('WindowsToolchainService');

  /// The official Build Tools bootstrapper — a ~4 MB stub that downloads the
  /// rest itself.
  static const bootstrapperUrl =
      'https://aka.ms/vs/17/release/vs_BuildTools.exe';

  /// Where `vswhere` lives. Its path is fixed by the installer and does not
  /// move between Visual Studio versions.
  static String get vsWherePath => p.join(
    Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
    'Microsoft Visual Studio',
    'Installer',
    'vswhere.exe',
  );

  static String get vsSetupPath => p.join(
    Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
    'Microsoft Visual Studio',
    'Installer',
    'setup.exe',
  );

  WindowsToolchain? _cache;

  void refresh() => _cache = null;

  /// Reads the machine's toolchain.
  Future<WindowsToolchain> detect({bool force = false}) async {
    if (_cache != null && !force) return _cache!;
    if (!_platform.isWindows) return const WindowsToolchain();

    final installs = await _visualStudioInstalls();
    final sdks = await _windowsSdks();
    return _cache = WindowsToolchain(installs: installs, sdks: sdks);
  }

  // ---- detection -----------------------------------------------------------

  Future<List<VisualStudioInstall>> _visualStudioInstalls() async {
    if (!File(vsWherePath).existsSync()) return const [];

    // Two calls: the JSON has no component list, so the second one asks which
    // installs carry the MSVC toolset and the paths are matched up.
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
      withCppTools: withCpp == null
          ? const {}
          : parseVsWherePaths(withCpp).toSet(),
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

  /// The kit root from the registry, then the version folders under it.
  Future<List<WindowsSdk>> _windowsSdks() async {
    try {
      final result = await _runner.run(
        'reg',
        [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Windows Kits\Installed Roots',
          '/v',
          'KitsRoot10',
        ],
        timeout: const Duration(seconds: 15),
      );
      if (!result.isSuccess) return const [];

      final root = parseKitsRoot(result.stdout);
      if (root == null) return const [];

      final include = Directory(p.join(root, 'Include'));
      if (!include.existsSync()) return const [];

      return parseSdkVersions(
        include.listSync().whereType<Directory>().map(
          (d) => p.basename(d.path),
        ),
        kitRoot: root,
      );
    } catch (e) {
      _log.fine('could not read the Windows Kits registry: $e');
      return const [];
    }
  }

  // ---- setup ---------------------------------------------------------------

  /// Installs Build Tools from scratch, with the C++ workload.
  Stream<WindowsSetupEvent> installBuildTools() async* {
    File? bootstrapper;
    try {
      yield const WindowsSetupEvent(
        stage: WindowsSetupStage.downloading,
        progress: 0,
      );
      bootstrapper = await _downloadBootstrapper((progress) {});

      yield* _runElevated(bootstrapper.path, [
        '--passive',
        '--wait',
        '--norestart',
        '--add',
        kBuildToolsWorkload,
        '--add',
        kVcToolsComponent,
        '--includeRecommended',
      ]);
    } on Failure catch (e) {
      yield WindowsSetupEvent(
        stage: WindowsSetupStage.failed,
        error: e.message,
      );
    } catch (e) {
      yield WindowsSetupEvent(stage: WindowsSetupStage.failed, error: '$e');
    } finally {
      try {
        if (bootstrapper != null && bootstrapper.existsSync()) {
          bootstrapper.deleteSync();
        }
      } catch (_) {}
    }
  }

  /// Adds the C++ workload to an install that has everything else.
  Stream<WindowsSetupEvent> addCppTools(VisualStudioInstall install) =>
      _modify(install, [
        'modify',
        '--installPath',
        install.installPath,
        '--add',
        install.cppWorkload,
        '--add',
        kVcToolsComponent,
        '--includeRecommended',
      ]);

  /// Updates an install to the newest build Microsoft ships.
  Stream<WindowsSetupEvent> update(VisualStudioInstall install) =>
      _modify(install, [
        'update',
        '--installPath',
        install.installPath,
      ]);

  /// Finishes an install that was interrupted.
  Stream<WindowsSetupEvent> repair(VisualStudioInstall install) =>
      _modify(install, [
        'repair',
        '--installPath',
        install.installPath,
      ]);

  Stream<WindowsSetupEvent> _modify(
    VisualStudioInstall install,
    List<String> arguments,
  ) async* {
    if (!File(vsSetupPath).existsSync()) {
      yield const WindowsSetupEvent(
        stage: WindowsSetupStage.failed,
        error: 'The Visual Studio Installer is not on this machine.',
      );
      return;
    }
    yield* _runElevated(vsSetupPath, [
      ...arguments,
      '--passive',
      '--wait',
      '--norestart',
    ]);
  }

  /// Asks Windows for elevation, then waits for the installer to exit.
  ///
  /// `Start-Process -Verb RunAs -Wait` is what makes the wait possible: the
  /// elevated child's output is unreachable, but its exit is not.
  Stream<WindowsSetupEvent> _runElevated(
    String executable,
    List<String> arguments,
  ) async* {
    yield const WindowsSetupEvent(stage: WindowsSetupStage.launching);

    final quoted = arguments.map((a) => "'${a.replaceAll("'", "''")}'").join(',');
    final script =
        "\$p = Start-Process -FilePath '${executable.replaceAll("'", "''")}' "
        '-Verb RunAs -Wait -PassThru -ArgumentList $quoted; '
        r'exit $p.ExitCode';

    yield const WindowsSetupEvent(stage: WindowsSetupStage.installing);
    final result = await _runner.run(
      'powershell',
      ['-NoProfile', '-Command', script],
      // Installing the C++ workload pulls gigabytes; it is slow on any line.
      timeout: const Duration(hours: 2),
    );

    if (result.isSuccess) {
      yield const WindowsSetupEvent(stage: WindowsSetupStage.done);
      return;
    }

    // 3010 is "success, reboot required" — the install did land.
    if (result.exitCode == 3010) {
      yield const WindowsSetupEvent(
        stage: WindowsSetupStage.done,
        error: 'Windows asked for a restart to finish the install.',
      );
      return;
    }

    yield WindowsSetupEvent(
      stage: WindowsSetupStage.failed,
      error: result.exitCode == 1602 || result.exitCode == 1223
          // 1223 is a declined UAC prompt, 1602 a cancelled installer.
          ? 'The installer was cancelled.'
          : 'The installer exited with code ${result.exitCode}.',
    );
  }

  Future<File> _downloadBootstrapper(void Function(double) onProgress) async {
    final support = await getApplicationSupportDirectory();
    final target = File(p.join(support.path, 'vs_BuildTools.exe'));
    await Dio().download(
      bootstrapperUrl,
      target.path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );
    return target;
  }
}
