import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../../core/di/injection.dart';
import '../../infrastructure/logging/dev_log_service.dart';
import '../common/compact_field.dart';
import '../common/confirm_dialog.dart';
import '../common/outlined_action_button.dart';
import '../common/task_window_title_bar.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Developer request-log viewer.
///
/// Reads the file-backed log rather than the live [Logger] stream, because this
/// runs in its own window — a separate isolate — and tails what the main window
/// writes.
class DevLogsPage extends StatefulWidget {
  const DevLogsPage({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<DevLogsPage> createState() => _DevLogsPageState();
}

class _DevLogsPageState extends State<DevLogsPage> {
  /// Rows past this many lines collapse; the JSON blobs from `--machine`
  /// output would otherwise bury everything around them.
  static const int _collapseAfterLines = 3;

  final DevLogService _service = getIt<DevLogService>();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  Timer? _timer;
  Timer? _searchDebounce;

  List<DevLogRecord> _records = const [];

  /// Held back while paused, flushed into [_records] on resume.
  List<DevLogRecord> _buffered = const [];

  String _query = '';
  Level _minLevel = Level.ALL;
  bool _paused = false;

  /// True while the view is pinned to the newest entry.
  bool _following = true;

  /// Entries that arrived while detached, for the "jump to latest" chip.
  int _unseen = 0;

  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _refresh(),
    );
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Within a row of the end still counts as pinned, so a stray wheel tick
    // doesn't detach the view.
    final atBottom = _scroll.offset >= _scroll.position.maxScrollExtent - 24;
    if (atBottom != _following) {
      setState(() {
        _following = atBottom;
        if (atBottom) _unseen = 0;
      });
    }
  }

  Future<void> _refresh() async {
    final records = await _service.readAll();
    if (!mounted) return;
    if (_paused) {
      // Keep reading, keep it off screen: pause is about a stable view, not
      // about dropping what happened while you read.
      _buffered = records;
      return;
    }
    final grew = records.length - _records.length;
    setState(() {
      _records = records;
      if (!_following && grew > 0) _unseen += grew;
    });
    if (_following) _jumpToLatest();
  }

  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _follow() {
    setState(() {
      _following = true;
      _unseen = 0;
    });
    _jumpToLatest();
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _following = false;
      } else {
        // Resume flushes whatever accumulated behind the freeze.
        if (_buffered.isNotEmpty) {
          _records = _buffered;
          _buffered = const [];
        }
        _following = true;
        _unseen = 0;
      }
    });
    if (!_paused) _jumpToLatest();
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _query = value);
    });
  }

  List<DevLogRecord> _visible() {
    final q = _query.trim().toLowerCase();
    return _records.where((r) {
      if (r.level < _minLevel) return false;
      if (q.isEmpty) return true;
      return r.message.toLowerCase().contains(q) ||
          r.logger.toLowerCase().contains(q);
    }).toList();
  }

  static String thousands(int n) => DevLogsPageFormat.thousands(n);

  Future<void> _copy(List<DevLogRecord> shown) async {
    // The full message, never the collapsed form — copying a truncated blob
    // would be worse than useless in a bug report.
    final text = shown
        .map((r) => '${r.timeStr} ${r.level.name} ${r.logger}: ${r.message}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _clear() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear ${thousands(_records.length)} log entries?',
      message: "This can't be undone.",
      confirmLabel: 'Clear',
    );
    if (!ok) return;
    await _service.clear();
    _expanded.clear();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shown = _visible();
    final filtered = shown.length != _records.length;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): _clear,
        const SingleActivator(LogicalKeyboardKey.end): _follow,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            _copy(shown),
      },
      child: FocusScope(
        autofocus: true,
        child: Column(
          children: [
            TaskWindowTitleBar(
              icon: FluentIcons.command_prompt,
              title: 'Developer logs',
              trailing: TitleBarChip(
                label: filtered
                    ? '${thousands(shown.length)} / '
                          '${thousands(_records.length)}'
                    : thousands(_records.length),
              ),
              onClose: widget.onClose,
            ),
            _toolbar(shown),
            Expanded(child: _list(palette, shown)),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(List<DevLogRecord> shown) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kTaskWindowInset,
        10,
        kTaskWindowInset,
        10,
      ),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              // Esc clears the filter rather than bubbling up to the window.
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  _search.clear();
                  _onQueryChanged('');
                },
              },
              child: CompactField(
                controller: _search,
                focusNode: _searchFocus,
                placeholder: 'Search logs…',
                onChanged: _onQueryChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CompactCombo<Level>(
            width: 140,
            value: _minLevel,
            items: const [
              CompactComboItem(value: Level.ALL, label: 'All levels'),
              CompactComboItem(value: Level.FINE, label: '≥ Fine'),
              CompactComboItem(value: Level.INFO, label: '≥ Info'),
              CompactComboItem(value: Level.WARNING, label: '≥ Warning'),
              CompactComboItem(value: Level.SEVERE, label: '≥ Severe'),
            ],
            onChanged: (v) => setState(() => _minLevel = v),
          ),
          const SizedBox(width: 8),
          OutlinedActionButton(
            icon: _paused ? FluentIcons.play : FluentIcons.pause,
            tooltip: _paused ? 'Resume' : 'Pause updates',
            dense: true,
            onPressed: _togglePause,
          ),
          const SizedBox(width: 8),
          OutlinedActionButton(
            icon: FluentIcons.copy,
            label: 'Copy',
            dense: true,
            tooltip: 'Copy shown entries',
            onPressed: () => _copy(shown),
          ),
          const SizedBox(width: 8),
          OutlinedActionButton(
            icon: FluentIcons.delete,
            label: 'Clear',
            dense: true,
            danger: true,
            onPressed: _clear,
          ),
        ],
      ),
    );
  }

  Widget _list(AppPalette palette, List<DevLogRecord> shown) {
    final text = AppTextStyles.fromPalette(palette);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        kTaskWindowInset,
        0,
        kTaskWindowInset,
        kTaskWindowInset,
      ),
      decoration: BoxDecoration(
        color: palette.logBg,
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
        border: Border.all(color: palette.border, width: AppShape.hairline),
      ),
      child: shown.isEmpty
          ? Center(child: Text('No log records yet.', style: text.caption))
          : Stack(
              children: [
                SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _LogRow(
                      record: shown[i],
                      expanded: _expanded.contains(i),
                      collapseAfterLines: _collapseAfterLines,
                      onToggle: () => setState(
                        () => _expanded.contains(i)
                            ? _expanded.remove(i)
                            : _expanded.add(i),
                      ),
                    ),
                  ),
                ),
                if (!_following)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _JumpChip(unseen: _unseen, onTap: _follow),
                  ),
              ],
            ),
    );
  }
}

/// Floating "you have scrolled away" affordance.
class _JumpChip extends StatelessWidget {
  const _JumpChip({required this.unseen, required this.onTap});

  final int unseen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            border: Border.all(
              color: palette.borderStrong,
              width: AppShape.hairline,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.down, size: 10, color: palette.textSecondary),
              const SizedBox(width: 7),
              Text(
                unseen > 0 ? 'Jump to latest · $unseen new' : 'Jump to latest',
                style: text.caption.copyWith(color: palette.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogRow extends StatefulWidget {
  const _LogRow({
    required this.record,
    required this.expanded,
    required this.collapseAfterLines,
    required this.onToggle,
  });

  final DevLogRecord record;
  final bool expanded;
  final int collapseAfterLines;
  final VoidCallback onToggle;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _hovered = false;
  TapGestureRecognizer? _toggleTap;

  @override
  void dispose() {
    _toggleTap?.dispose();
    super.dispose();
  }

  /// Wrapping width isn't known here, so the record's own newlines are the
  /// signal for "this is a blob, not a line".
  bool get _isLong =>
      '\n'.allMatches(widget.record.message).length + 1 >
      widget.collapseAfterLines;

  String get _shown {
    if (widget.expanded || !_isLong) return widget.record.message;
    return widget.record.message
        .split('\n')
        .take(widget.collapseAfterLines)
        .join('\n');
  }

  Color _levelColor(AppPalette palette) {
    final level = widget.record.level;
    if (level >= Level.SEVERE) return palette.statusError;
    if (level >= Level.WARNING) return palette.statusWarn;
    if (level >= Level.INFO) return palette.textSecondary;
    return palette.logTrace;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    _toggleTap?.dispose();
    _toggleTap = TapGestureRecognizer()..onTap = widget.onToggle;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        color: _hovered ? palette.surfaceRaised : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.record.timeStr,
              style: text.monoLog.copyWith(color: palette.textMuted),
            ),
            const SizedBox(width: 10),
            SizedBox(
              // Fixed slot so messages line up whatever the level is called.
              width: 46,
              child: Text(
                widget.record.level.name,
                style: text.monoLog.copyWith(color: _levelColor(palette)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: text.monoLog,
                  children: [
                    TextSpan(
                      text: '${widget.record.logger}: ',
                      style: text.monoLog.copyWith(color: palette.textMuted),
                    ),
                    TextSpan(text: _shown),
                    if (_isLong)
                      TextSpan(
                        text: widget.expanded ? '  collapse' : '  … expand',
                        style: text.monoLog.copyWith(color: palette.accent),
                        recognizer: _toggleTap,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Number formatting for the viewer's count pill.
///
/// Split out so it can be exercised without standing up a window.
class DevLogsPageFormat {
  const DevLogsPageFormat._();

  /// 6400 → "6,400". The count sits in the title bar, where a bare run of
  /// digits is hard to size up at a glance.
  static String thousands(int n) {
    final digits = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
