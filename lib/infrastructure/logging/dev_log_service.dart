import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One captured log record (parsed from the log file).
class DevLogRecord {
  DevLogRecord(this.timeStr, this.level, this.logger, this.message);

  final String timeStr;
  final Level level;
  final String logger;
  final String message;
}

/// File-backed capture of every `logging` record so a SEPARATE window (a
/// different isolate) can tail the main window's command/request flow.
@lazySingleton
class DevLogService {
  static const int _maxBytes = 4 * 1024 * 1024;
  File? _file;

  Future<File> _resolve() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _file = File(p.join(dir.path, 'dev-log.log'));
  }

  /// Path to the log file (for reference).
  Future<String> path() async => (await _resolve()).path;

  /// Subscribes to the root logger and appends records to the file. Call once,
  /// only in windows that produce logs (main / create / console — NOT the
  /// viewer window itself).
  Future<void> attach() async {
    final file = await _resolve();
    Logger.root.onRecord.listen((r) => _append(file, r));
  }

  void _append(File file, LogRecord r) {
    final msg = r.message.replaceAll('\n', ' ').replaceAll('|', '¦');
    final line = '${_ts(r.time)}|${r.level.name}|${r.loggerName}|$msg\n';
    try {
      file.writeAsStringSync(line, mode: FileMode.append, flush: false);
      if (file.lengthSync() > _maxBytes) {
        final data = file.readAsStringSync();
        file.writeAsStringSync(data.substring(data.length - _maxBytes ~/ 2));
      }
    } catch (_) {}
  }

  /// Reads and parses all records currently in the file.
  Future<List<DevLogRecord>> readAll() async {
    final file = await _resolve();
    if (!file.existsSync()) return const [];
    try {
      final lines = const LineSplitter().convert(await file.readAsString());
      return lines
          .map(_parse)
          .whereType<DevLogRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clear() async {
    final file = await _resolve();
    if (file.existsSync()) await file.writeAsString('');
  }

  static DevLogRecord? _parse(String line) {
    if (line.isEmpty) return null;
    final parts = line.split('|');
    if (parts.length < 4) return null;
    final level = Level.LEVELS.firstWhere(
      (l) => l.name == parts[1],
      orElse: () => Level.INFO,
    );
    return DevLogRecord(
      parts[0],
      level,
      parts[2],
      parts.sublist(3).join('|'),
    );
  }

  static String _ts(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${three(t.millisecond)}';
  }
}
