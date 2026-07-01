import 'package:fluent_ui/fluent_ui.dart' show ChangeNotifier;
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

/// One captured log record.
class DevLogRecord {
  DevLogRecord(this.time, this.level, this.logger, this.message);

  final DateTime time;
  final Level level;
  final String logger;
  final String message;
}

/// In-memory ring buffer capturing every `logging` record (command executions,
/// warnings, errors) for the developer log viewer.
@lazySingleton
class DevLogService extends ChangeNotifier {
  static const int _capacity = 3000;
  final List<DevLogRecord> _records = [];
  bool _attached = false;

  List<DevLogRecord> get records => List.unmodifiable(_records);

  /// Subscribes to the root logger. Safe to call once.
  void attach() {
    if (_attached) return;
    _attached = true;
    Logger.root.onRecord.listen((r) {
      _records.add(DevLogRecord(r.time, r.level, r.loggerName, r.message));
      if (_records.length > _capacity) {
        _records.removeRange(0, _records.length - _capacity);
      }
      notifyListeners();
    });
  }

  void clear() {
    _records.clear();
    notifyListeners();
  }
}
