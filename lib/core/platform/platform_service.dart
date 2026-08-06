import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Everything that differs between Windows, Linux and macOS.
///
/// The rule this exists to enforce: `Platform.isWindows` and friends appear
/// *inside* an implementation of this and nowhere else. Code that wants "the
/// sdkmanager script" or "where JDKs live" asks for it rather than branching on
/// the host, which is what makes the rest of the app portable and testable
/// against a platform it is not running on.
///
/// This is the first pass and covers paths and executable naming only. Process
/// spawning, kill-trees, environment persistence, file-manager reveal and
/// window capabilities still branch at their call sites; they move here next.
abstract class PlatformService {
  /// `windows`, `linux` or `macos`.
  String get operatingSystem;

  bool get isWindows => operatingSystem == 'windows';
  bool get isLinux => operatingSystem == 'linux';
  bool get isMacos => operatingSystem == 'macos';

  // ---- Executable naming ---------------------------------------------------

  /// A compiled binary's file name: `adb` → `adb.exe` on Windows.
  String executableName(String base);

  /// A wrapper script's file name: `sdkmanager` → `sdkmanager.bat` on Windows.
  String scriptName(String base);

  /// What to invoke to run Flutter.
  String get flutterExecutable => scriptName('flutter');

  // ---- Well-known locations ------------------------------------------------

  /// Where an Android SDK is normally installed, best guess first. Only the
  /// paths this platform actually uses — the caller checks which exist.
  List<String> get defaultAndroidSdkPaths;

  /// Directories that hold JDK installations, one sub-directory per JDK.
  List<String> get jdkSearchPaths;

  /// Chromium-family browsers, most likely first. Absolute executable paths.
  List<String> get browserCandidates;

  /// The folder holding `<name>.avd` directories, or null when even the home
  /// directory is unknown.
  ///
  /// `ANDROID_AVD_HOME` and `ANDROID_USER_HOME` are honoured on every platform,
  /// not just the Unix ones: the emulator reads them everywhere, and an SDK
  /// relocated with them was previously invisible to this app on Windows too.
  String? get avdHome;

  /// The archive Google publishes the command-line tools as, per platform.
  String get cmdlineToolsArchivePrefix;
}

/// Path builders fixed to a platform's separators.
///
/// `package:path`'s top-level helpers follow the *running* platform, so on a
/// Windows machine they would build `/home/dev\Android\Sdk` for the Linux
/// implementation. Explicit contexts are what make each implementation describe
/// its own platform — and what make all three testable from any one of them.
final p.Context _posix = p.Context(style: p.Style.posix);
final p.Context _win = p.Context(style: p.Style.windows);

/// The implementation for the host this process is running on.
@module
abstract class PlatformModule {
  @lazySingleton
  PlatformService get platform => hostPlatformService();
}

/// The host's implementation, resolved once.
///
/// For the static helpers that cannot be handed one — a disk scan testing
/// thousands of candidates has no instance to reach for, and building a new
/// service per candidate would be silly.
PlatformService get hostPlatform => _host ??= hostPlatformService();
PlatformService? _host;

/// Picks the implementation matching the host.
///
/// Anything that is not Windows or macOS is treated as Linux: the app targets
/// the three desktops, and the Unix layout is the sane default for the rest.
PlatformService hostPlatformService({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  if (Platform.isWindows) return WindowsPlatformService(environment: env);
  if (Platform.isMacOS) return MacosPlatformService(environment: env);
  return LinuxPlatformService(environment: env);
}

/// Shared behaviour: the two Unix platforms differ only in where things live.
abstract class _UnixPlatformService implements PlatformService {
  _UnixPlatformService({required this.environment});

  final Map<String, String> environment;


  String? get home => environment['HOME'];

  @override
  bool get isWindows => operatingSystem == 'windows';
  @override
  bool get isLinux => operatingSystem == 'linux';
  @override
  bool get isMacos => operatingSystem == 'macos';

  @override
  String get flutterExecutable => scriptName('flutter');

  /// Unix has no extension convention for either kind.
  @override
  String executableName(String base) => base;

  @override
  String scriptName(String base) => base;

  @override
  String? get avdHome =>
      resolveAvdHome(environment, home, context: _posix);
}

/// Windows: `.exe` for binaries, `.bat` for the SDK's wrapper scripts.
class WindowsPlatformService implements PlatformService {
  WindowsPlatformService({Map<String, String>? environment})
      : environment = environment ?? Platform.environment;

  final Map<String, String> environment;


  @override
  String get operatingSystem => 'windows';

  @override
  bool get isWindows => true;
  @override
  bool get isLinux => false;
  @override
  bool get isMacos => false;

  @override
  String executableName(String base) => '$base.exe';

  @override
  String scriptName(String base) => '$base.bat';

  @override
  String get flutterExecutable => scriptName('flutter');

  @override
  List<String> get defaultAndroidSdkPaths {
    final localAppData = environment['LOCALAPPDATA'];
    final userProfile = environment['USERPROFILE'];
    return [
      if (localAppData != null) _win.join(localAppData, 'Android', 'Sdk'),
      if (userProfile != null) ...[
        _win.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk'),
        _win.join(userProfile, 'Android', 'Sdk'),
      ],
    ];
  }

  /// Read from `%ProgramFiles%` rather than hardcoded: an install on a machine
  /// whose Program Files sits on another drive is invisible otherwise.
  @override
  List<String> get jdkSearchPaths {
    final programFiles = environment['ProgramFiles'] ?? r'C:\Program Files';
    return [
      for (final vendor in const [
        'Microsoft',
        'Eclipse Adoptium',
        'Java',
        'Amazon Corretto',
        'Zulu',
      ])
        _win.join(programFiles, vendor),
    ];
  }

  @override
  List<String> get browserCandidates {
    final localAppData = environment['LOCALAPPDATA'];
    return [
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
      if (localAppData != null)
        _win.join(localAppData, 'Google', 'Chrome', 'Application',
            'chrome.exe'),
      r'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe',
      r'C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe',
      r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    ];
  }

  @override
  String? get avdHome => resolveAvdHome(
        environment,
        environment['USERPROFILE'] ?? environment['HOME'],
        context: _win,
      );

  @override
  String get cmdlineToolsArchivePrefix => 'commandlinetools-win';
}

/// Linux: SDK under `~/Android/Sdk`, JDKs under `/usr/lib/jvm`.
class LinuxPlatformService extends _UnixPlatformService {
  LinuxPlatformService({Map<String, String>? environment})
      : super(environment: environment ?? Platform.environment);

  @override
  String get operatingSystem => 'linux';

  @override
  List<String> get defaultAndroidSdkPaths => [
        if (home != null) ...[
          _posix.join(home!, 'Android', 'Sdk'),
          // Some installers still use the lowercase spelling.
          _posix.join(home!, 'Android', 'sdk'),
        ],
      ];

  @override
  List<String> get jdkSearchPaths => const ['/usr/lib/jvm'];

  @override
  List<String> get browserCandidates => [
        '/usr/bin/google-chrome',
        '/usr/bin/google-chrome-stable',
        '/usr/bin/chromium',
        '/usr/bin/chromium-browser',
        '/snap/bin/chromium',
        '/usr/bin/brave-browser',
        '/var/lib/flatpak/exports/bin/com.google.Chrome',
        if (home != null)
          _posix.join(home!, '.local', 'share', 'flatpak', 'exports', 'bin',
              'com.google.Chrome'),
      ];

  @override
  String get cmdlineToolsArchivePrefix => 'commandlinetools-linux';
}

/// macOS: SDK under `~/Library/Android/sdk`, JDKs as `.jdk` bundles.
class MacosPlatformService extends _UnixPlatformService {
  MacosPlatformService({Map<String, String>? environment})
      : super(environment: environment ?? Platform.environment);

  @override
  String get operatingSystem => 'macos';

  @override
  List<String> get defaultAndroidSdkPaths => [
        if (home != null) _posix.join(home!, 'Library', 'Android', 'sdk'),
      ];

  /// The JDKs directory holds bundles, and the JDK itself is
  /// `<bundle>/Contents/Home` — see [macosJdkHome].
  @override
  List<String> get jdkSearchPaths =>
      const ['/Library/Java/JavaVirtualMachines'];

  @override
  List<String> get browserCandidates => [
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
        '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
        '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
        if (home != null)
          _posix.join(home!, 'Applications', 'Google Chrome.app', 'Contents',
              'MacOS', 'Google Chrome'),
      ];

  @override
  String get cmdlineToolsArchivePrefix => 'commandlinetools-mac';
}

/// The AVD folder, from the variables the emulator itself reads.
///
/// Order matches the emulator's own: `ANDROID_AVD_HOME` wins outright, then
/// `ANDROID_USER_HOME`'s `avd`, then the `.android/avd` under the home
/// directory. Pure so the precedence can be tested without an SDK.
String? resolveAvdHome(
  Map<String, String> environment,
  String? home, {
  p.Context? context,
}) {
  final path = context ?? p.context;
  final explicit = environment['ANDROID_AVD_HOME'];
  if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();

  final userHome = environment['ANDROID_USER_HOME'];
  if (userHome != null && userHome.trim().isNotEmpty) {
    return path.join(userHome.trim(), 'avd');
  }

  // The legacy variable, still honoured by the emulator.
  final sdkHome = environment['ANDROID_SDK_HOME'];
  if (sdkHome != null && sdkHome.trim().isNotEmpty) {
    return path.join(sdkHome.trim(), '.android', 'avd');
  }

  if (home == null || home.trim().isEmpty) return null;
  return path.join(home.trim(), '.android', 'avd');
}

/// The real JDK directory inside a macOS `.jdk` bundle.
///
/// `/Library/Java/JavaVirtualMachines/temurin-21.jdk` is not a JDK; the thing
/// with `bin/java` in it is `<bundle>/Contents/Home`.
String macosJdkHome(String bundlePath) =>
    p.posix.join(bundlePath, 'Contents', 'Home');
