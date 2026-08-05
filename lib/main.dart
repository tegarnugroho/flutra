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
import 'presentation/window/create_emulator_window.dart';
import 'presentation/window/dev_logs_window.dart';
import 'presentation/window/emulator_console_window.dart';

/// Business id marking the standalone Create-Emulator window.
const String kCreateEmulatorWindow = 'createEmulator';

/// Business id marking the standalone Emulator-Console window.
const String kEmulatorConsoleWindow = 'emulatorConsole';

/// Business id marking the standalone Developer-Logs window.
const String kDevLogsWindow = 'devLogs';

Future<void> main(List<String> args) async {
  _setupLogging();
  WidgetsFlutterBinding.ensureInitialized();
  // On hot restart the Dart code reloads but native plugins do not, so the
  // window_manager channel may be briefly unavailable. Guard it so the app
  // still boots instead of throwing an unhandled MissingPluginException.
  try {
    await windowManager.ensureInitialized();
    // Below this the two-pane pages (SDK manager) start to overflow.
    await windowManager.setMinimumSize(const Size(960, 640));
  } on MissingPluginException catch (e) {
    Logger('main').warning('window_manager unavailable: ${e.message}');
  }
  configureDependencies();

  // Every window (main and sub-windows) runs this same entrypoint. The current
  // engine's arguments tell us which one we are.
  final arguments = await _currentWindowArguments();
  final decoded = _tryDecode(arguments);
  final businessId = decoded?['businessId'];

  // Only the main window draws its own caption; the sub-windows keep the native
  // one. Done here, before any IO, so the native bar isn't visible at startup.
  if (businessId == null) await _hideNativeTitleBar();

  // Capture the log/command flow for producing windows, but NOT the viewer
  // window itself (it only reads the shared log file).
  if (businessId != kDevLogsWindow) {
    await getIt<DevLogService>().attach();
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

  // Main window: load persisted settings and apply theme / SDK override, then
  // purge any soft-deleted folders older than 24h.
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
  // The sub-window engine spawned by desktop_multi_window does NOT register
  // window_manager, so we don't touch it here. The window is shown by native
  // (hiddenAtLaunch: false) at its default size with a standard title bar.
  final controller = await WindowController.fromCurrentEngine();
  runApp(
    CreateEmulatorWindowApp(
      windowController: controller,
      dark: args['dark'] == true,
    ),
  );
}

Future<void> _runEmulatorConsoleWindow(Map<String, dynamic> args) async {
  final controller = await WindowController.fromCurrentEngine();
  runApp(
    EmulatorConsoleWindowApp(
      windowController: controller,
      dark: args['dark'] == true,
      avdName: args['avd'] as String? ?? '',
    ),
  );
}

/// Removes the native caption so [CustomTitleBar] can draw it instead.
///
/// [TitleBarStyle.hidden] only strips the caption band — the resize borders and
/// Windows Snap keep working. `setAsFrameless()` would remove those too, so it
/// is deliberately not used.
Future<void> _hideNativeTitleBar() async {
  if (!Platform.isWindows) return;
  try {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  } on MissingPluginException catch (_) {
    // window_manager unavailable — keep the native caption.
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
  final controller = await WindowController.fromCurrentEngine();
  runApp(
    DevLogsWindowApp(windowController: controller, dark: args['dark'] == true),
  );
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
