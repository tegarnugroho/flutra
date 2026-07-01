import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

import 'core/di/injection.dart';
import 'presentation/app.dart';
import 'presentation/window/create_emulator_window.dart';

/// Business id marking the standalone Create-Emulator window.
const String kCreateEmulatorWindow = 'createEmulator';

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
  final controller = await WindowController.fromCurrentEngine();
  // Size/center/title are nice-to-haves via window_manager; guard them so a
  // missing native plugin (e.g. after a hot restart) never crashes the window.
  try {
    const options = WindowOptions(
      size: Size(940, 720),
      center: true,
      title: 'Create Emulator',
    );
    unawaited(windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setTitle('Create Emulator');
      await windowManager.show();
      await windowManager.focus();
    }));
  } on MissingPluginException catch (e) {
    Logger('main').warning('window sizing unavailable: ${e.message}');
  }
  runApp(CreateEmulatorWindowApp(
    windowController: controller,
    dark: args['dark'] == true,
  ));
}

void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name} ${record.loggerName}: ${record.message}');
  });
}
