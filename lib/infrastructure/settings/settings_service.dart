import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/settings/app_settings.dart';

/// Loads and persists [AppSettings] to a JSON file in the app support folder.
@lazySingleton
class SettingsService {
  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'settings.json'));
  }

  /// Reads settings from disk; falls back to defaults on any error.
  Future<AppSettings> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return _settings;
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        _settings = AppSettings.fromJson(json);
      }
    } catch (_) {
      // keep defaults
    }
    return _settings;
  }

  Future<void> save(AppSettings settings) async {
    _settings = settings;
    try {
      final file = await _file();
      await file.writeAsString(const JsonEncoder.withIndent('  ')
          .convert(settings.toJson()));
    } catch (_) {
      // best-effort persistence
    }
  }
}
