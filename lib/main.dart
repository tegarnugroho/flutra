import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

import 'application/settings/settings_cubit.dart';
import 'core/di/injection.dart';
import 'presentation/app.dart';
import 'presentation/window/create_emulator_window.dart';
import 'presentation/window/emulator_console_window.dart';

/// Business id marking the standalone Create-Emulator window.
const String kCreateEmulatorWindow = 'createEmulator';

/// Business id marking the standalone Emulator-Console window.
const String kEmulatorConsoleWindow = 'emulatorConsole';

Future<void> main(List<String> args) async {
  _setupLogging();
  WidgetsFlutterBinding.ensureInitialized();
  // On hot restart the Dart code reloads but native plugins do not, so the
  // window_manager channel may be briefly unavailable. Guard it so the app
  // still boots instead of throwing an unhandled MissingPluginException.
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

  if (decoded != null && decoded['businessId'] == kCreateEmulatorWindow) {
    await _runCreateEmulatorWindow(decoded);
    return;
  }
  if (decoded != null && decoded['businessId'] == kEmulatorConsoleWindow) {
    await _runEmulatorConsoleWindow(decoded);
    return;
  }

  // Main window: load persisted settings and apply theme / SDK override.
  await getIt<SettingsCubit>().init();
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
  runApp(CreateEmulatorWindowApp(
    windowController: controller,
    dark: args['dark'] == true,
  ));
}

Future<void> _runEmulatorConsoleWindow(Map<String, dynamic> args) async {
  final controller = await WindowController.fromCurrentEngine();
  runApp(EmulatorConsoleWindowApp(
    windowController: controller,
    dark: args['dark'] == true,
    avdName: args['avd'] as String? ?? '',
  ));
}

void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name} ${record.loggerName}: ${record.message}');
  });
}
