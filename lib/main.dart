import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

import 'application/settings/settings_cubit.dart';
import 'core/di/injection.dart';
import 'infrastructure/logging/dev_log_service.dart';
import 'infrastructure/settings/legacy_data_migration.dart';
import 'infrastructure/settings/settings_service.dart';
import 'infrastructure/trash/trash_service.dart';
import 'presentation/app.dart';
import 'presentation/window/about_window.dart';
import 'presentation/window/create_emulator_window.dart';
import 'presentation/window/dev_logs_window.dart';
import 'presentation/window/emulator_console_window.dart';
import 'presentation/theme/app_colors.dart';
import 'presentation/window/window_placement.dart';

/// Business id marking the standalone Create-Emulator window.
const String kCreateEmulatorWindow = 'createEmulator';

/// Business id marking the standalone Emulator-Console window.
const String kEmulatorConsoleWindow = 'emulatorConsole';

/// Business id marking the standalone Developer-Logs window.
const String kDevLogsWindow = 'devLogs';

/// Business id marking the standalone About window.
const String kAboutWindow = 'about';

/// Times this window's boot, in debug builds only.
///
/// Every step below runs before the first frame, so "opening feels heavy" is
/// measurable rather than a guess: the log line says which part of the boot
/// the time actually went to.
class _BootTrace {
  final Stopwatch _clock = Stopwatch()..start();
  final List<String> _steps = [];
  String _window = 'main';

  void mark(String step) {
    if (kDebugMode) _steps.add('$step=${_clock.elapsedMilliseconds}ms');
  }

  void name(String window) => _window = window;

  /// Called once the window is actually on screen.
  void shown() {
    if (!kDebugMode) return;
    _steps.add('shown=${_clock.elapsedMilliseconds}ms');
    Logger('boot').info('$_window: ${_steps.join(' ')}');
  }
}

final _boot = _BootTrace();

/// The windows created hidden, which reveal themselves once their first frame
/// is ready. Nothing can flash on these before [_revealWindow] runs.
const Set<String> _hiddenAtLaunch = {
  kCreateEmulatorWindow,
  kEmulatorConsoleWindow,
  kDevLogsWindow,
  kAboutWindow,
};

/// Set by [_placeTaskWindow] and awaited by [_revealWindow], so a hidden window
/// still never appears wearing the native caption, and never appears white.
Future<void> _windowChrome = Future<void>.value();

Future<void> main(List<String> args) async {
  _setupLogging();
  WidgetsFlutterBinding.ensureInitialized();
  _boot.mark('binding');
  // On hot restart the Dart code reloads but native plugins do not, so the
  // window_manager channel may be briefly unavailable. Guard it so the app
  // still boots instead of throwing an unhandled MissingPluginException.
  // The runner registers plugins for sub-window engines too (see main.cpp), so
  // this succeeds in every window — each one then sizes itself below.
  try {
    await windowManager.ensureInitialized();
  } on MissingPluginException catch (e) {
    Logger('main').warning('window_manager unavailable: ${e.message}');
  }
  configureDependencies();
  _boot.mark('di');

  // Every window (main and sub-windows) runs this same entrypoint. The current
  // engine's arguments tell us which one we are.
  final arguments = await _currentWindowArguments();
  final decoded = _tryDecode(arguments);
  final businessId = decoded?['businessId'];
  _boot
    ..name(businessId as String? ?? 'main')
    ..mark('args');

  // Every window draws its own caption. Hiding the native one costs ~110ms of
  // SetWindowPos, so the windows that launch hidden defer it and overlap it
  // with building their first frame instead — see _placeTaskWindow. The ones
  // that are visible from the start still pay it up front, or the native bar
  // would flash.
  if (!_hiddenAtLaunch.contains(businessId)) {
    // The main window's theme is not known until its settings load, so it only
    // loses the caption here; a sub-window carries its theme in its arguments.
    if (businessId == null) {
      await _hideNativeTitleBar();
    } else {
      await _applyWindowChrome(dark: decoded?['dark'] == true);
    }
    _boot.mark('chrome');
  }
  if (businessId == null) {
    // Below this the two-pane pages (SDK manager) start to overflow.
    await _tryWindow(() => windowManager.setMinimumSize(const Size(960, 640)));
  }

  // Capture the log/command flow for producing windows, but NOT the viewer
  // window itself (it only reads the shared log file).
  //
  // Not awaited: attaching resolves the app-support directory, which is a
  // plugin round trip, and nothing about drawing the first frame depends on
  // it. The cost of that is a few startup log lines that may land after the
  // listener does — which is worth more to the window than to the log.
  if (businessId != kDevLogsWindow) {
    unawaited(getIt<DevLogService>().attach());
  }

  if (businessId == kCreateEmulatorWindow) {
    await _runCreateEmulatorWindow(decoded!);
    return;
  }
  if (businessId == kEmulatorConsoleWindow) {
    await _runEmulatorConsoleWindow(decoded!);
    return;
  }
  if (businessId == kDevLogsWindow) {
    await _runDevLogsWindow(decoded!);
    return;
  }
  if (businessId == kAboutWindow) {
    await _runAboutWindow(decoded!);
    return;
  }

  // Main window: carry over anything the pre-rename build left behind, then
  // load persisted settings and apply theme / SDK override, and purge any
  // soft-deleted folders older than 24h.
  //
  // The migration runs before the first read, or settings would be written
  // fresh over the top of what it was about to copy.
  await getIt<LegacyDataMigration>().run();
  await getIt<SettingsCubit>().init();
  await _restoreWindowBounds();
  unawaited(getIt<TrashService>().purgeExpired());
  runApp(const AndroidSdkManagerApp());
}

/// Reads the arguments string passed to this engine, tolerating the case where
/// the multi-window plugin is unavailable (then we are the main window).
Future<String> _currentWindowArguments() async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    return controller.arguments;
  } catch (_) {
    return '';
  }
}

Map<String, dynamic>? _tryDecode(String arguments) {
  if (arguments.isEmpty) return null;
  try {
    return jsonDecode(arguments) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<void> _runCreateEmulatorWindow(Map<String, dynamic> args) async {
  // Position first, while the window is still hidden — see _revealWindow.
  await _placeTaskWindow(args, kWizardWindowSize, kWizardWindowMinSize);
  final controller = await WindowController.fromCurrentEngine();
  runApp(
    CreateEmulatorWindowApp(
      windowController: controller,
      dark: args['dark'] == true,
    ),
  );
  _revealWindow();
}

Future<void> _runEmulatorConsoleWindow(Map<String, dynamic> args) async {
  await _placeTaskWindow(args, kConsoleWindowSize, kConsoleWindowMinSize);
  final controller = await WindowController.fromCurrentEngine();
  runApp(
    EmulatorConsoleWindowApp(
      windowController: controller,
      dark: args['dark'] == true,
      avdName: args['avd'] as String? ?? '',
    ),
  );
  _revealWindow();
}

/// Removes the native caption so [CustomTitleBar] can draw it instead.
///
/// [TitleBarStyle.hidden] only strips the caption band — the resize borders and
/// Windows Snap keep working. `setAsFrameless()` would remove those too, so it
/// is deliberately not used.
Future<void> _hideNativeTitleBar() async {
  if (!Platform.isWindows) return;
  await _tryWindow(
    () => windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    ),
  );
}

/// Applies the frame the opener worked out for this window, before anything is
/// visible.
///
/// The rect arrives in the arguments already centred (see
/// `centeredOverMainWindow`); this side only applies it. Falling back to
/// centring on this window's own display is the defensive path for a missing or
/// malformed argument — never show unpositioned.
Future<void> _placeTaskWindow(
  Map<String, dynamic> args,
  Size defaultSize,
  Size minSize,
) async {
  _boot.mark('place');
  await _tryWindow(() async {
    await windowManager.setMinimumSize(minSize);
    final frame = (args['frame'] as List?)?.cast<num>();
    if (frame == null || frame.length != 4) {
      await windowManager.setSize(defaultSize);
      await windowManager.setAlignment(Alignment.center);
      return;
    }
    await windowManager.setBounds(
      Rect.fromLTWH(
        frame[0].toDouble(),
        frame[1].toDouble(),
        frame[2].toDouble(),
        frame[3].toDouble(),
      ),
    );
  });
  // Started, not awaited: the window stays hidden until _revealWindow awaits
  // this, so the ~110ms it costs runs alongside the widget build instead of
  // before it. Kicked off after the bounds above, never alongside them — two
  // window calls in flight at once is not worth the milliseconds.
  _windowChrome = _applyWindowChrome(dark: args['dark'] == true);
}

/// Hides the native caption and paints the window the app's own background.
///
/// The background matters for the gap between `show()` and the first raster
/// reaching the screen: a hidden window does not rasterise, so those pixels
/// come from the native brush, which is white by default. On a big window —
/// the log viewer — that gap is long enough to read as a white flash.
Future<void> _applyWindowChrome({required bool dark}) async {
  await _tryWindow(
    () => windowManager.setBackgroundColor(
      dark ? AppColors.windowBg : AppColors.windowBgLight,
    ),
  );
  await _hideNativeTitleBar();
}

/// Reveals a window created hidden, once its first frame has been rasterised.
///
/// The only `show()` in the sub-window flow, and it runs strictly after the
/// bounds above are applied — so the first painted frame is already in its
/// final place. Ordering, not a timer: the post-frame callback fires when the
/// frame is actually on the surface.
void _revealWindow() {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // The caption swap and the background must have landed before anything is
    // visible.
    await _windowChrome;
    _boot.mark('chrome');
    await _tryWindow(() => windowManager.show());
    _boot.shown();
  });
}

/// Runs a window_manager call, tolerating an engine where the plugin is
/// missing (hot restart, or a platform that has no such window).
Future<void> _tryWindow(Future<void> Function() action) async {
  try {
    await action();
  } on MissingPluginException catch (_) {
    // Nothing to configure — the window keeps its native defaults.
  } catch (_) {}
}

/// Restores the last main-window position/size from settings.
Future<void> _restoreWindowBounds() async {
  final s = getIt<SettingsService>().settings;
  if (!s.hasWindowBounds) return;
  try {
    await windowManager.setBounds(
      Rect.fromLTWH(s.windowX!, s.windowY!, s.windowWidth!, s.windowHeight!),
    );
  } on MissingPluginException catch (_) {
    // window_manager unavailable — keep native default bounds.
  } catch (_) {}
}

Future<void> _runDevLogsWindow(Map<String, dynamic> args) async {
  await _placeTaskWindow(args, kDevLogsWindowSize, kDevLogsWindowMinSize);
  final controller = await WindowController.fromCurrentEngine();
  runApp(
    DevLogsWindowApp(windowController: controller, dark: args['dark'] == true),
  );
  _revealWindow();
}

Future<void> _runAboutWindow(Map<String, dynamic> args) async {
  await _placeTaskWindow(args, kAboutWindowSize, kAboutWindowSize);
  // A fixed card: nothing in it reflows, so resizing only ever makes it worse.
  await _tryWindow(() => windowManager.setResizable(false));
  final controller = await WindowController.fromCurrentEngine();
  runApp(
    AboutWindowApp(windowController: controller, dark: args['dark'] == true),
  );
  _revealWindow();
}

void _setupLogging() {
  // Capture everything (incl. FINE command-exec logs) for the dev log; only
  // print INFO+ to the console to avoid noise.
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (record.level >= Level.INFO) {
      // ignore: avoid_print
      print('${record.level.name} ${record.loggerName}: ${record.message}');
    }
  });
}
