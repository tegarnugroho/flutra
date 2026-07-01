import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import 'trash_entry.dart';

/// Soft-delete store: moves folders into a sibling `.asm-trash` directory
/// (instant, same-volume rename) and keeps them for [_ttl] so they can be
/// restored. A JSON registry in the app-support folder tracks entries.
@lazySingleton
class TrashService {
  TrashService(this._runner);

  final CommandRunner _runner;
  static final Logger _log = Logger('TrashService');
  static const Duration _ttl = Duration(hours: 24);

  Future<File> _registry() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'trash.json'));
  }

  Future<List<TrashEntry>> _read() async {
    try {
      final file = await _registry();
      if (!file.existsSync()) return [];
      final json = jsonDecode(await file.readAsString());
      if (json is List) {
        return json
            .whereType<Map<String, dynamic>>()
            .map(TrashEntry.fromJson)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _write(List<TrashEntry> entries) async {
    final file = await _registry();
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
            entries.map((e) => e.toJson()).toList()));
  }

  /// Moves [path] into the trash and records it. Kills processes holding files
  /// inside [path] first (Windows) so the move isn't blocked.
  Future<TrashEntry> trash(String path, {required String label}) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw FileSystemFailure('Folder not found: $path');
    }
    await _killProcessesUnder(path);

    final parent = p.dirname(path);
    final trashRoot = Directory(p.join(parent, '.asm-trash'));
    if (!trashRoot.existsSync()) trashRoot.createSync(recursive: true);

    final now = DateTime.now();
    final stamp = now.microsecondsSinceEpoch.toString();
    final trashPath =
        p.join(trashRoot.path, '${p.basename(path)}-$stamp');

    try {
      await dir.rename(trashPath); // same volume → instant, no copy
    } on FileSystemException catch (e) {
      throw FileSystemFailure(
        'Could not move the folder to trash. Close programs using it and try '
        'again.',
        cause: e,
      );
    }

    final entry = TrashEntry(
      id: stamp,
      label: label,
      originalPath: path,
      trashPath: trashPath,
      deletedAt: now,
    );
    final entries = await _read()..add(entry);
    await _write(entries);
    return entry;
  }

  /// Deletes trash entries older than 24h. Call on app startup.
  Future<void> purgeExpired() async {
    final now = DateTime.now();
    final entries = await _read();
    final keep = <TrashEntry>[];
    for (final e in entries) {
      final expired = now.difference(e.deletedAt) >= _ttl;
      final dir = Directory(e.trashPath);
      if (expired || !dir.existsSync()) {
        if (dir.existsSync()) {
          try {
            dir.deleteSync(recursive: true);
            _log.info('purged expired trash: ${e.label} (${e.originalPath})');
          } catch (err) {
            _log.warning('failed to purge ${e.trashPath}: $err');
            keep.add(e); // keep so we retry next launch
            continue;
          }
        }
      } else {
        keep.add(e);
      }
    }
    if (keep.length != entries.length) await _write(keep);
  }

  /// Live trash entries (folder still present), newest first.
  Future<List<TrashEntry>> list() async {
    final entries = await _read();
    final live = entries
        .where((e) => Directory(e.trashPath).existsSync())
        .toList()
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return live;
  }

  /// Restores [entry] to its original location. Fails if something already
  /// occupies the original path.
  Future<void> restore(TrashEntry entry) async {
    final src = Directory(entry.trashPath);
    if (!src.existsSync()) {
      throw FileSystemFailure('The trashed folder is no longer available.');
    }
    if (Directory(entry.originalPath).existsSync()) {
      throw FileSystemFailure(
          'Something already exists at ${entry.originalPath}.');
    }
    Directory(p.dirname(entry.originalPath)).createSync(recursive: true);
    await src.rename(entry.originalPath);
    final entries = await _read()..removeWhere((e) => e.id == entry.id);
    await _write(entries);
  }

  Future<void> _killProcessesUnder(String path) async {
    if (!Platform.isWindows) return;
    final script = "Get-CimInstance Win32_Process | "
        "Where-Object { \$_.ExecutablePath -and "
        "\$_.ExecutablePath -like '$path\\*' } | "
        "ForEach-Object { try { Stop-Process -Id \$_.ProcessId -Force "
        "-ErrorAction SilentlyContinue } catch {} }";
    try {
      await _runner.run('powershell', ['-NoProfile', '-Command', script],
          timeout: const Duration(seconds: 30));
    } catch (_) {}
  }
}
