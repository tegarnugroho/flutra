import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../core/command/session_environment.dart';
import '../../core/platform/platform_service.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../sdk/flutter_locator.dart';
import '../sdk/sdk_locator.dart';
import '../sdk/sdk_scan_service.dart';

/// One update from a running fix.
sealed class FixEvent {
  const FixEvent();
}

/// A line of tool output, or a note from the fix itself.
class FixLogged extends FixEvent {
  const FixLogged(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

/// The fix ended. Always the last event.
class FixFinished extends FixEvent {
  const FixFinished(this.outcome);

  final FixOutcome outcome;
}

/// What a finished fix leaves behind.
class FixOutcome {
  const FixOutcome({
    required this.success,
    this.restartRequired = false,
    this.note,
    this.blocksRerun = false,
  });

  const FixOutcome.failed(String this.note)
      : success = false,
        restartRequired = false,
        blocksRerun = false;

  final bool success;

  /// The change only reaches processes started later — the user's terminals,
  /// and anything the app spawns after a restart.
  final bool restartRequired;

  /// One line for the UI: what happened, or why it didn't.
  final String? note;

  /// Something is still running outside the app (the Visual Studio installer),
  /// so re-running doctor now would report the old state.
  final bool blocksRerun;
}

/// A choice a guided fix needs before it can run.
class FixChoice {
  const FixChoice({required this.value, required this.label, this.detail});

  /// What the executor receives — a path, in every current fix.
  final String value;

  final String label;

  /// Second line: a version, or where it was found.
  final String? detail;
}

/// What a fix is given to work with.
class FixContext {
  const FixContext({this.androidSdkRoot, this.flutterRoot, this.choice});

  final String? androidSdkRoot;
  final String? flutterRoot;

  /// The option the user picked, for guided fixes.
  final String? choice;
}

/// One problem's remedy.
///
/// Kept behind an interface so a macOS/Linux implementation can be dropped in
/// later without the cubit or the UI learning anything new.
abstract class DoctorFixExecutor {
  /// The [DoctorIssue.id] this handles.
  String get issueId;

  /// Whether this fix can run on the host at all.
  bool get isSupported => Platform.isWindows;

  /// Options for a guided fix, in the order they should be offered. Empty for
  /// an automatic one.
  Future<List<FixChoice>> options(FixContext ctx) async => const [];

  /// The commands the confirm dialog shows before anything runs. Exactly what
  /// will be executed — never a paraphrase.
  List<String> preview(FixContext ctx);

  /// Runs the fix, reporting progress. Ends with exactly one [FixFinished].
  Stream<FixEvent> execute(FixContext ctx);
}

/// Owns the executors and the context they run in.
@lazySingleton
class DoctorFixService {
  DoctorFixService(
    this._runner,
    this._sdkLocator,
    this._flutterLocator,
    this._scanner,
    this._session,
    this._sdk,
    this._flutter,
    this._platform,
  );

  final CommandRunner _runner;
  final SdkLocator _sdkLocator;
  final FlutterLocator _flutterLocator;
  final SdkScanService _scanner;
  final SessionEnvironment _session;
  final SdkRepository _sdk;
  final FlutterRepository _flutter;
  final PlatformService _platform;

  late final Map<String, DoctorFixExecutor> _executors = {
    for (final executor in <DoctorFixExecutor>[
      AcceptAndroidLicencesFix(_runner),
      InstallCmdlineToolsFix(_sdk, _sdkLocator),
      SelectAndroidSdkFix(_runner, _scanner),
      SelectJdkFix(_runner, _platform),
      SelectBrowserFix(_runner, _session, _platform),
      RepairVisualStudioFix(_runner),
      AddFlutterToPathFix(_flutter),
    ])
      executor.issueId: executor,
  };

  /// The executor for [issueId], or null when the issue is a redirect the UI
  /// handles on its own.
  DoctorFixExecutor? executorFor(String issueId) => _executors[issueId];

  /// The paths the fixes resolve against, read fresh each time — a previous
  /// fix may have just changed them.
  FixContext context({String? choice}) => FixContext(
        androidSdkRoot: _sdkLocator.sdkRoot,
        flutterRoot: _flutterLocator.root,
        choice: choice,
      );
}

// ---------------------------------------------------------------------------
// Shared plumbing
// ---------------------------------------------------------------------------

/// Default ceiling for a fix that only runs local commands.
const Duration kFixTimeout = Duration(seconds: 120);

/// Ceiling for anything that downloads or installs SDK packages.
const Duration kInstallTimeout = Duration(minutes: 15);

/// Runs [executable], streaming stdout and stderr as log events, and answering
/// prompts that match [autoAnswer] with "y".
///
/// Kills the whole process tree on timeout: sdkmanager and the licence prompt
/// both spawn a java child that outlives a plain kill.
Stream<FixEvent> runStreaming(
  CommandRunner runner,
  String executable,
  List<String> arguments, {
  Duration timeout = kFixTimeout,
  RegExp? autoAnswer,
  String onFailure = 'The command failed.',
}) async* {
  final RunningCommand command;
  try {
    command = await runner.start(executable, arguments);
  } catch (e) {
    yield FixLogged('$e', isError: true);
    yield FixFinished(FixOutcome.failed(onFailure));
    return;
  }

  var timedOut = false;
  final timer = Timer(timeout, () {
    timedOut = true;
    _killTree(command.pid);
  });

  // Prompts arrive on the same stream as everything else, so the answer has to
  // be written while the output is still being read.
  if (autoAnswer != null) {
    command.output.listen((line) {
      if (autoAnswer.hasMatch(line.text)) {
        try {
          command.writeLine('y');
        } catch (_) {
          // The process exited between the prompt and the answer.
        }
      }
    });
  }

  await for (final line in command.output) {
    yield FixLogged(line.text, isError: line.isError);
  }
  final result = await command.result;
  timer.cancel();

  if (timedOut) {
    yield const FixLogged('Timed out — the process tree was killed.',
        isError: true);
    yield FixFinished(const FixOutcome.failed(
        'The command did not finish in time and was stopped.'));
    return;
  }
  yield FixFinished(result.isSuccess
      ? const FixOutcome(success: true)
      : FixOutcome.failed('$onFailure (exit ${result.exitCode})'));
}

/// Best-effort `taskkill /T /F`, for a process that owns children.
void _killTree(int pid) {
  try {
    Process.runSync('taskkill', ['/T', '/F', '/PID', '$pid']);
  } catch (_) {
    // Already gone, or no permission — the timeout is reported either way.
  }
}

/// The `flutter` launcher, since these run it directly rather than via PATH.
String _flutterExe() => Platform.isWindows ? 'flutter.bat' : 'flutter';

// ---------------------------------------------------------------------------
// 1. Android licences
// ---------------------------------------------------------------------------

/// Accepts every pending Android SDK licence.
class AcceptAndroidLicencesFix implements DoctorFixExecutor {
  AcceptAndroidLicencesFix(this._runner);

  final CommandRunner _runner;

  /// Both shapes the prompt takes across sdkmanager versions.
  static final RegExp prompt = RegExp(r'\(y/N\)|Accept\?', caseSensitive: false);

  @override
  String get issueId => 'android_licenses';

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<List<FixChoice>> options(FixContext ctx) async => const [];

  @override
  List<String> preview(FixContext ctx) =>
      ['${_flutterExe()} doctor --android-licenses'];

  @override
  Stream<FixEvent> execute(FixContext ctx) => runStreaming(
        _runner,
        _flutterExe(),
        ['doctor', '--android-licenses'],
        autoAnswer: prompt,
        onFailure: 'Could not accept the licences.',
      );
}

// ---------------------------------------------------------------------------
// 2. cmdline-tools
// ---------------------------------------------------------------------------

/// Installs `cmdline-tools;latest` through sdkmanager.
///
/// Goes through [SdkRepository.install] rather than spawning sdkmanager here:
/// that path already answers the licence prompts and, on Windows, runs from a
/// throwaway copy so the tool can overwrite its own jars.
class InstallCmdlineToolsFix implements DoctorFixExecutor {
  InstallCmdlineToolsFix(this._sdk, this._locator);

  final SdkRepository _sdk;
  final SdkLocator _locator;

  @override
  String get issueId => 'cmdline_tools_missing';

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<List<FixChoice>> options(FixContext ctx) async => const [];

  @override
  List<String> preview(FixContext ctx) =>
      ['sdkmanager --install "cmdline-tools;latest"'];

  @override
  Stream<FixEvent> execute(FixContext ctx) async* {
    if (_locator.sdkManager == null) {
      // No sdkmanager means nothing can install anything — including itself.
      // TODO(bootstrap): download commandlinetools-win-<build>_latest.zip and
      // unpack it into <sdkRoot>\cmdline-tools\latest to recover from a fully
      // empty SDK. Needs the exact build number pinned somewhere shared with
      // the SDK Manager module, which today has no download path either.
      yield const FixLogged(
        'No sdkmanager was found in the Android SDK, so there is nothing to '
        'install with. Install the command-line tools from Android Studio, or '
        'point the SDK path in Settings at an SDK that has them.',
        isError: true,
      );
      yield FixFinished(const FixOutcome.failed(
          'sdkmanager is missing — install it from Android Studio first.'));
      return;
    }

    final RunningCommand command;
    try {
      command = await _sdk.install('cmdline-tools;latest');
    } catch (e) {
      yield FixLogged('$e', isError: true);
      yield FixFinished(
          const FixOutcome.failed('Could not start the installation.'));
      return;
    }

    final timer = Timer(kInstallTimeout, () => _killTree(command.pid));
    await for (final line in command.output) {
      yield FixLogged(line.text, isError: line.isError);
    }
    final result = await command.result;
    timer.cancel();
    yield FixFinished(result.isSuccess
        ? const FixOutcome(success: true)
        : FixOutcome.failed(
            'sdkmanager exited with ${result.exitCode}.'));
  }
}

// ---------------------------------------------------------------------------
// 3. Android SDK location
// ---------------------------------------------------------------------------

/// Tells Flutter which Android SDK to use, from the ones found on disk.
class SelectAndroidSdkFix implements DoctorFixExecutor {
  SelectAndroidSdkFix(this._runner, this._scanner);

  final CommandRunner _runner;
  final SdkScanService _scanner;

  @override
  String get issueId => 'android_sdk_missing';

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<List<FixChoice>> options(FixContext ctx) async {
    final found = await _scanner.findAndroidSdks();
    return [
      for (final path in found)
        FixChoice(value: path, label: path, detail: 'Android SDK'),
    ];
  }

  @override
  List<String> preview(FixContext ctx) => [
        'flutter config --android-sdk "${ctx.choice ?? '<sdk>'}"',
        'setx ANDROID_HOME "${ctx.choice ?? '<sdk>'}"',
      ];

  @override
  Stream<FixEvent> execute(FixContext ctx) async* {
    final path = ctx.choice;
    if (path == null || path.isEmpty) {
      yield FixFinished(const FixOutcome.failed('No SDK folder was chosen.'));
      return;
    }
    if (!SdkLocator.looksLikeAndroidSdk(path)) {
      yield FixFinished(FixOutcome.failed(
          '"$path" does not hold the Android tools — pick the SDK root.'));
      return;
    }

    final config = await _runner.run(
      _flutterExe(),
      ['config', '--android-sdk', path],
      timeout: kFixTimeout,
    );
    yield FixLogged(config.combinedOutput.trim(), isError: !config.isSuccess);
    if (!config.isSuccess) {
      yield FixFinished(const FixOutcome.failed(
          'flutter config would not take that SDK path.'));
      return;
    }

    // ANDROID_HOME is what everything *else* reads — the app's own locator
    // included, on the next launch.
    final env = await _runner.run('setx', ['ANDROID_HOME', path],
        timeout: const Duration(seconds: 30));
    yield FixLogged(env.combinedOutput.trim());

    yield FixFinished(FixOutcome(
      success: true,
      restartRequired: true,
      note: 'ANDROID_HOME was set to $path. Open a new terminal for it to '
          'take effect there.',
    ));
  }
}

// ---------------------------------------------------------------------------
// 4. JDK
// ---------------------------------------------------------------------------

/// Points Flutter at a JDK 17+ install.
class SelectJdkFix implements DoctorFixExecutor {
  SelectJdkFix(this._runner, this._platform);

  final CommandRunner _runner;
  final PlatformService _platform;

  /// Android's Gradle plugin needs 17 or newer; older JDKs fail the build with
  /// an error that looks nothing like a JDK problem.
  static const int minimumMajor = 17;

  @override
  String get issueId => 'jdk_missing_or_invalid';

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<List<FixChoice>> options(FixContext ctx) async {
    final candidates = <String>{};
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.trim().isNotEmpty) {
      candidates.add(javaHome.trim());
    }
    for (final root in _platform.jdkSearchPaths) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      try {
        for (final child in dir.listSync().whereType<Directory>()) {
          // macOS keeps JDKs as .jdk bundles: the directory holding bin/java is
          // <bundle>/Contents/Home, not the bundle itself.
          for (final home in [
            child.path,
            if (_platform.isMacos) macosJdkHome(child.path),
          ]) {
            if (File(p.join(home, 'bin', _platform.executableName('java')))
                .existsSync()) {
              candidates.add(home);
              break;
            }
          }
        }
      } catch (_) {
        // Unreadable folder: nothing to offer from it.
      }
    }

    final choices = <FixChoice>[];
    for (final path in candidates) {
      final version = await _majorVersion(path);
      if (version == null || version < minimumMajor) continue;
      choices.add(FixChoice(
        value: path,
        label: p.basename(path),
        detail: 'Java $version · $path',
      ));
    }
    choices.sort((a, b) => a.label.compareTo(b.label));
    return choices;
  }

  /// The major version [jdkPath] reports, or null when it will not run.
  Future<int?> _majorVersion(String jdkPath) async {
    final exe = p.join(jdkPath, 'bin', _platform.executableName('java'));
    if (!File(exe).existsSync()) return null;
    try {
      final result =
          await _runner.run(exe, ['-version'], timeout: const Duration(seconds: 20));
      return parseMajorVersion(result.combinedOutput);
    } catch (_) {
      return null;
    }
  }

  /// Reads `openjdk version "17.0.20"` / `java version "1.8.0_401"`.
  ///
  /// The 1.x scheme is Java 8 and older, where the major version is the second
  /// component — those never satisfy [minimumMajor], but they must not parse
  /// as version 1 and look *newer* than nothing.
  static int? parseMajorVersion(String output) {
    final match =
        RegExp(r'version "(\d+)(?:\.(\d+))?').firstMatch(output);
    if (match == null) return null;
    final first = int.tryParse(match.group(1) ?? '');
    if (first == null) return null;
    if (first != 1) return first;
    return int.tryParse(match.group(2) ?? '');
  }

  @override
  List<String> preview(FixContext ctx) =>
      ['flutter config --jdk-dir "${ctx.choice ?? '<jdk>'}"'];

  @override
  Stream<FixEvent> execute(FixContext ctx) async* {
    final path = ctx.choice;
    if (path == null || path.isEmpty) {
      yield FixFinished(const FixOutcome.failed('No JDK was chosen.'));
      return;
    }
    yield* runStreaming(
      _runner,
      _flutterExe(),
      ['config', '--jdk-dir', path],
      onFailure: 'flutter config would not take that JDK.',
    ).map((event) => event is FixFinished && event.outcome.success
        // flutter config is read per invocation, so the next doctor run in
        // this session already sees it.
        ? const FixFinished(FixOutcome(
            success: true,
            note: 'Flutter will use this JDK from now on.',
          ))
        : event);
  }
}

// ---------------------------------------------------------------------------
// 5. Chrome / browser
// ---------------------------------------------------------------------------

/// Records a Chromium browser for web builds.
class SelectBrowserFix implements DoctorFixExecutor {
  SelectBrowserFix(this._runner, this._session, this._platform);

  final CommandRunner _runner;
  final SessionEnvironment _session;
  final PlatformService _platform;

  static const String variable = 'CHROME_EXECUTABLE';


  @override
  String get issueId => 'chrome_missing';

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<List<FixChoice>> options(FixContext ctx) async => [
        for (final path in _platform.browserCandidates)
          if (File(path).existsSync())
            FixChoice(
              value: path,
              label: p.basenameWithoutExtension(path),
              detail: path,
            ),
      ];

  @override
  List<String> preview(FixContext ctx) =>
      ['setx $variable "${ctx.choice ?? '<browser.exe>'}"'];

  @override
  Stream<FixEvent> execute(FixContext ctx) async* {
    final path = ctx.choice;
    if (path == null || path.isEmpty) {
      yield FixFinished(const FixOutcome.failed('No browser was chosen.'));
      return;
    }
    if (!File(path).existsSync()) {
      yield FixFinished(FixOutcome.failed('"$path" is not there.'));
      return;
    }

    // In-process first: this is what makes the doctor re-run below pass
    // without waiting for a restart.
    _session.set(variable, path);
    yield FixLogged('$variable set for this session → $path');

    final result = await _runner.run('setx', [variable, path],
        timeout: const Duration(seconds: 30));
    yield FixLogged(result.combinedOutput.trim(),
        isError: !result.isSuccess);
    if (!result.isSuccess) {
      yield FixFinished(const FixOutcome(
        success: true,
        note: 'Set for this app, but saving it for other terminals failed.',
      ));
      return;
    }

    yield FixFinished(const FixOutcome(
      success: true,
      note: 'Saved. Terminals already open keep the old value until they are '
          'reopened.',
    ));
  }
}

// ---------------------------------------------------------------------------
// 6. Visual Studio workload
// ---------------------------------------------------------------------------

/// Adds the C++ desktop workload through the Visual Studio Installer.
class RepairVisualStudioFix implements DoctorFixExecutor {
  RepairVisualStudioFix(this._runner);

  final CommandRunner _runner;

  static const String installerDir =
      r'C:\Program Files (x86)\Microsoft Visual Studio\Installer';
  static const String workload = 'Microsoft.VisualStudio.Workload.NativeDesktop';

  @override
  String get issueId => 'vs_incomplete';

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<List<FixChoice>> options(FixContext ctx) async => const [];

  @override
  List<String> preview(FixContext ctx) => [
        'setup.exe modify --installPath "<vs>" --add $workload '
            '--includeRecommended --passive',
      ];

  @override
  Stream<FixEvent> execute(FixContext ctx) async* {
    final setup = File(p.join(installerDir, 'setup.exe'));
    if (!setup.existsSync()) {
      yield FixFinished(const FixOutcome.failed(
          'The Visual Studio Installer is not on this machine — install '
          'Visual Studio first.'));
      return;
    }

    final vswhere = p.join(installerDir, 'vswhere.exe');
    final located = await _runner.run(
      vswhere,
      ['-latest', '-property', 'installationPath'],
      timeout: const Duration(seconds: 30),
    );
    final installPath = located.stdout.trim();
    if (!located.isSuccess || installPath.isEmpty) {
      yield FixFinished(const FixOutcome.failed(
          'Could not work out where Visual Studio is installed.'));
      return;
    }
    yield FixLogged('Visual Studio found at $installPath');

    // The installer needs elevation, and an elevated child cannot hand its
    // output back to this process — so this launches it and stops there.
    final launch = await _runner.run('powershell', [
      '-NoProfile',
      '-Command',
      "Start-Process -FilePath '${setup.path}' -Verb RunAs -ArgumentList "
          "'modify','--installPath','\"$installPath\"','--add','$workload',"
          "'--includeRecommended','--passive'",
    ], timeout: const Duration(seconds: 60));

    if (!launch.isSuccess) {
      yield FixLogged(launch.combinedOutput.trim(), isError: true);
      yield FixFinished(const FixOutcome.failed(
          'The installer would not start — the elevation prompt may have been '
          'declined.'));
      return;
    }

    yield const FixLogged(
      'The Visual Studio Installer is running in its own window. It can take '
      'several minutes.',
    );
    yield FixFinished(const FixOutcome(
      success: true,
      blocksRerun: true,
      note: 'Visual Studio Installer launched. Re-run doctor once it has '
          'finished.',
    ));
  }
}

// ---------------------------------------------------------------------------
// 7. Flutter on PATH
// ---------------------------------------------------------------------------

/// Appends the Flutter SDK's `bin` to the user PATH.
///
/// Delegates to [FlutterRepository.addSdkToPath], which reads and rewrites the
/// user PATH through PowerShell. `setx PATH` is not used anywhere here: it
/// truncates at 1024 characters and would quietly destroy a long PATH.
class AddFlutterToPathFix implements DoctorFixExecutor {
  AddFlutterToPathFix(this._flutter);

  final FlutterRepository _flutter;

  @override
  String get issueId => 'flutter_not_on_path';

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<List<FixChoice>> options(FixContext ctx) async => const [];

  @override
  List<String> preview(FixContext ctx) => [
        'Append "${p.join(ctx.flutterRoot ?? '<flutter>', 'bin')}" to the user '
            'PATH',
      ];

  @override
  Stream<FixEvent> execute(FixContext ctx) async* {
    final root = ctx.flutterRoot;
    if (root == null || root.isEmpty) {
      yield FixFinished(const FixOutcome.failed(
          'The Flutter SDK folder is not known — set it in Settings first.'));
      return;
    }
    yield FixLogged('Adding ${p.join(root, 'bin')} to the user PATH…');
    try {
      await _flutter.addSdkToPath(root);
    } catch (e) {
      yield FixLogged('$e', isError: true);
      yield FixFinished(const FixOutcome.failed('Could not update PATH.'));
      return;
    }
    yield FixFinished(const FixOutcome(
      success: true,
      restartRequired: true,
      note: 'PATH updated. New terminals — and this app after a restart — will '
          'find "flutter".',
    ));
  }
}
