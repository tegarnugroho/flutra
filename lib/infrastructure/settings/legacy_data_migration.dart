import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/platform/platform_service.dart';

/// Carries user data over from the folder the app used before it was renamed.
///
/// On Windows `path_provider` builds the support directory out of the
/// executable's `CompanyName` and `ProductName`, so renaming the product moved
/// it — settings, the cached release index, the storage report and the dev log
/// were all suddenly somewhere the app no longer looked.
///
/// Copies rather than moves, and leaves the old folder alone: an upgrade that
/// goes wrong should be able to fall back to the previous build with its data
/// intact. Removing the old folder is a later release's job.
@lazySingleton
class LegacyDataMigration {
  LegacyDataMigration(this._platform);

  final PlatformService _platform;

  static final Logger _log = Logger('LegacyDataMigration');

  /// `%APPDATA%\com.androidsdkmanager\android_sdk_manager`, the pre-rename
  /// location. Only ever existed on Windows — the other platforms had no
  /// release under the old name.
  static const String legacyCompany = 'com.androidsdkmanager';
  static const String legacyProduct = 'android_sdk_manager';

  /// Runs once at startup, before anything reads settings.
  Future<void> run() async {
    if (!_platform.isWindows) return;

    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return;

    try {
      final from = Directory(p.join(appData, legacyCompany, legacyProduct));
      final to = await getApplicationSupportDirectory();
      await migrate(from: from, to: to);
    } catch (e) {
      // A failed migration must never stop the app from starting; the worst
      // case is a fresh-looking install with the old data still on disk.
      _log.warning('could not carry the old data over: $e');
    }
  }

  /// Copies every file in [from] into [to], unless [to] already holds data.
  ///
  /// Returns the number of files copied. Separate from [run] and free of any
  /// path lookups so it can be exercised against temporary directories.
  ///
  /// "Already holds data" is deliberately any file at all: a user who has run
  /// the renamed build even once has state worth more than a copy of an older
  /// one, and re-copying every launch would undo their changes.
  static Future<int> migrate({
    required Directory from,
    required Directory to,
  }) async {
    if (!from.existsSync()) return 0;
    if (to.existsSync() && to.listSync().isNotEmpty) return 0;
    if (p.equals(from.path, to.path)) return 0;

    await to.create(recursive: true);
    var copied = 0;
    for (final entity in from.listSync(recursive: true)) {
      final relative = p.relative(entity.path, from: from.path);
      final target = p.join(to.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
        copied++;
      }
    }
    if (copied > 0) {
      _log.info('carried $copied file(s) over from ${from.path}');
    }
    return copied;
  }
}
