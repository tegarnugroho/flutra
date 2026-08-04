import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../../core/di/injection.dart';
import '../../infrastructure/logging/dev_log_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Developer request-log viewer. Reads the file-backed log so it works in a
/// standalone window (separate isolate) and tails the main window's flow.
class DevLogsPage extends StatefulWidget {
  const DevLogsPage({super.key});

  @override
  State<DevLogsPage> createState() => _DevLogsPageState();
}

class _DevLogsPageState extends State<DevLogsPage> {
  final DevLogService _service = getIt<DevLogService>();
  final ScrollController _scroll = ScrollController();
  Timer? _timer;
  List<DevLogRecord> _records = const [];
  String _query = '';
  Level _minLevel = Level.ALL;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final records = await _service.readAll();
    if (!mounted) return;
    setState(() => _records = records);
  }

  List<DevLogRecord> _filtered() {
    final q = _query.trim().toLowerCase();
    return _records.where((r) {
      if (r.level < _minLevel) return false;
      if (q.isEmpty) return true;
      return r.message.toLowerCase().contains(q) ||
          r.logger.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final records = _filtered();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Developer Logs'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.copy),
              label: const Text('Copy'),
              onPressed: () => _copy(context, records),
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.clear),
              label: const Text('Clear'),
              onPressed: () async {
                await _service.clear();
                await _refresh();
              },
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
                      ComboBoxItem(value: Level.SEVERE, child: Text('≥ Severe')),
                    ],
                    onChanged: (v) => setState(() => _minLevel = v ?? Level.ALL),
                  ),
                ),
                const Spacer(),
                Text('${records.length} shown • ${_records.length} total',
                    style: FluentTheme.of(context).typography.caption),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              decoration: BoxDecoration(
                color: AppColors.logBg,
                borderRadius: BorderRadius.circular(AppShape.radiusGroup),
                border: Border.all(
                    color: AppColors.border, width: AppShape.hairline),
              ),
              child: records.isEmpty
                  ? const Center(
                      child: Text('No log records yet.',
                          style: AppTextStyles.caption),
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(10),
                        itemCount: records.length,
                        itemBuilder: (context, i) => _LogRow(record: records[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, List<DevLogRecord> records) async {
    final text = records
        .map((r) => '${r.timeStr} ${r.level.name} ${r.logger}: ${r.message}')
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
    final palette = AppPalette.of(context);
    final color = record.level >= Level.SEVERE
        ? palette.statusError
        : record.level >= Level.WARNING
            ? palette.statusWarn
            : record.level >= Level.INFO
                ? palette.textSecondary
                : palette.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Text(
        '${record.timeStr}  ${record.level.name.padRight(7)} '
        '${record.logger}: ${record.message}',
        style: AppTextStyles.monoLog.copyWith(color: color),
      ),
    );
  }
}
