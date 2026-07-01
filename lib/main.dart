import 'package:fluent_ui/fluent_ui.dart';
import 'package:logging/logging.dart';

import 'core/di/injection.dart';
import 'presentation/app.dart';

void main() {
  _setupLogging();
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  runApp(const AndroidSdkManagerApp());
}

void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name} ${record.loggerName}: ${record.message}');
  });
}
