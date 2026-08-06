import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

import 'application/settings/settings_cubit.dart';
import 'core/di/injection.dart';
import 'infrastructure/logging/dev_log_service.dart';
import 'infrastructure/settings/settings_service.dart';
import 'infrastructure/trash/trash_service.dart';
import 'presentation/app.dart';
import 'presentation/window/task_window_host.dart';
import 'presentation/window/task_window_routes.dart';
import 'presentation/window/warm_window_pool.dart';

Future<void> main(List<String> args) async {
  _setupLogging();
  WidgetsFlutterBinding.ensureInitialized();
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

  // Every window (main and sub-windows) runs this same entrypoint. The current
  // engine's arguments tell us which one we are.
  final arguments = await _currentWindowArguments();
  final decoded = _tryDecode(arguments);
  final businessId = decoded?['businessId'];

  // Every window draws its own caption. Done before any IO so the native bar
  // isn't visible at startup.
  await _hideNativeTitleBar();
  if (businessId == null) {
    // Below this the two-pane pages (SDK manager) start to overflow.
    await _tryWindow(() => windowManager.setMinimumSize(const Size(960, 640)));
  }

  // Capture the log/command flow for producing windows, but NOT the viewer
  // window itself (it only reads the shared log file).
  if (businessId != kDevLogsWindow) {
    await getIt<DevLogService>().attach();
  }

  if (businessId != null) {
    await _runTaskWindow(businessId, decoded!);
    return;
  }

  // Main window: load persisted settings and apply theme / SDK override, then
  // purge any soft-deleted folders older than 24h.
  await getIt<SettingsCubit>().init();
  await _restoreWindowBounds();
  unawaited(getIt<TrashService>().purgeExpired());
  runApp(const AndroidSdkManagerApp());
  // Boot the standby window once this one is on screen and idle. Opening a
  // task window costs an engine start; this is where that cost gets paid,
  // instead of between a click and the window appearing.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    getIt<WarmWindowPool>().scheduleWarmUp();
  });
}

/// Runs any sub-window.
///
/// Every task window is the same host with a different route, so a window
/// created ahead of time can be told what to become later — see
/// [TaskWindowHost] and [WarmWindowPool]. The launch-argument path below is the
/// one a cold open takes, and the fallback whenever the warm one is unusable.
Future<void> _runTaskWindow(String route, Map<String, dynamic> args) async {
  // Chrome before anything is visible: the first painted frame is already the
  // right size, in the right place. A standby window skips it — it has no job
  // yet, and gets its chrome when it is handed one.
  if (route != kStandbyWindow) await applyWindowChrome(route, args);
  final controller = await WindowController.fromCurrentEngine();
  runApp(TaskWindowHost(
    controller: controller,
    initialRoute: route,
    initialArgs: args,
  ));
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
