import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../../core/di/injection.dart';
import '../../infrastructure/logging/dev_log_service.dart';

/// Developer request-log viewer: shows every captured log record (command
/// executions, warnings, errors) with level filtering and search.
class DevLogsPage extends StatefulWidget {
  const DevLogsPage({super.key});

  @override
  State<DevLogsPage> createState() => _DevLogsPageState();
}

class _DevLogsPageState extends State<DevLogsPage> {
  final DevLogService _service = getIt<DevLogService>();
  final ScrollController _scroll = ScrollController();
  String _query = '';
  Level _minLevel = Level.ALL;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<DevLogRecord> _filtered() {
    final q = _query.trim().toLowerCase();
    return _service.records.where((r) {
      if (r.level < _minLevel) return false;
      if (q.isEmpty) return true;
      return r.message.toLowerCase().contains(q) ||
          r.logger.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Developer Logs'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.copy),
              label: const Text('Copy'),
              onPressed: () => _copy(context),
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.clear),
              label: const Text('Clear'),
              onPressed: () => _service.clear(),
            ),
          ],
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: TextBox(
                    placeholder: 'Search logs…',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(FluentIcons.search, size: 14),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: ComboBox<Level>(
                    isExpanded: true,
                    value: _minLevel,
                    items: const [
                      ComboBoxItem(value: Level.ALL, child: Text('All levels')),
                      ComboBoxItem(value: Level.FINE, child: Text('≥ Fine')),
                      ComboBoxItem(value: Level.INFO, child: Text('≥ Info')),
                      ComboBoxItem(
                          value: Level.WARNING, child: Text('≥ Warning')),
                      ComboBoxItem(
                          value: Level.SEVERE, child: Text('≥ Severe')),
                    ],
                    onChanged: (v) =>
                        setState(() => _minLevel = v ?? Level.ALL),
                  ),
                ),
                const Spacer(),
                AnimatedBuilder(
                  animation: _service,
                  builder: (context, _) => Text(
                    '${_service.records.length} records',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0C),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: AnimatedBuilder(
                animation: _service,
                builder: (context, _) {
                  final records = _filtered();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scroll.hasClients) {
                      _scroll.jumpTo(_scroll.position.maxScrollExtent);
                    }
                  });
                  if (records.isEmpty) {
                    return const Center(
                      child: Text('No log records.',
                          style: TextStyle(
                              color: Color(0xFF7A7A7A), fontSize: 12)),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: records.length,
                    itemBuilder: (context, i) => _LogRow(record: records[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final text = _filtered()
        .map((r) => '${_fmt(r.time)} ${r.level.name} ${r.logger}: ${r.message}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    await displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('Copied'),
        content: const Text('Logs copied to clipboard.'),
        severity: InfoBarSeverity.success,
        onClose: close,
      );
    });
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.record});

  final DevLogRecord record;

  @override
  Widget build(BuildContext context) {
    final color = record.level >= Level.SEVERE
        ? const Color(0xFFFF6B6B)
        : record.level >= Level.WARNING
            ? const Color(0xFFFFB454)
            : record.level >= Level.INFO
                ? const Color(0xFF9ECE6A)
                : const Color(0xFF9AA5B1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: SelectableText(
        '${_fmt(record.time)}  ${record.level.name.padRight(7)} '
        '${record.logger}: ${record.message}',
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 12,
          height: 1.35,
          color: color,
        ),
      ),
    );
  }
}

String _fmt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
}
