import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/entities/log_line.dart';

/// A terminal-style, auto-scrolling, colorized view of streamed log lines.
///
/// Auto-scroll sticks to the bottom unless the user scrolls up (to inspect
/// history), and resumes when they return to the bottom.
class LiveLogView extends StatefulWidget {
  const LiveLogView({super.key, required this.lines, this.emptyHint});

  final List<LogLine> lines;
  final String? emptyHint;

  @override
  State<LiveLogView> createState() => _LiveLogViewState();
}

class _LiveLogViewState extends State<LiveLogView> {
  final ScrollController _scroll = ScrollController();
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.offset >= _scroll.position.maxScrollExtent - 40;
    if (atBottom != _stickToBottom) {
      setState(() => _stickToBottom = atBottom);
    }
  }

  @override
  void didUpdateWidget(covariant LiveLogView old) {
    super.didUpdateWidget(old);
    if (_stickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Stack(
        children: [
          if (widget.lines.isEmpty)
            Center(
              child: Text(
                widget.emptyHint ?? 'Waiting for output…',
                style: const TextStyle(color: Color(0xFF7A7A7A), fontSize: 12),
              ),
            )
          else
            Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                itemCount: widget.lines.length,
                itemBuilder: (context, i) => _LogRow(line: widget.lines[i]),
              ),
            ),
          if (!_stickToBottom)
            Positioned(
              right: 12,
              bottom: 12,
              child: Button(
                onPressed: () {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  setState(() => _stickToBottom = true);
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.down, size: 12),
                    SizedBox(width: 6),
                    Text('Jump to end'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.line});

  final LogLine line;

  static const _fatal = Color(0xFFFF5370);
  static const _error = Color(0xFFFF6B6B);
  static const _warn = Color(0xFFFFB454);
  static const _info = Color(0xFF9ECE6A);
  static const _debug = Color(0xFF7AA2F7);
  static const _verbose = Color(0xFF9AA5B1);
  static const _plain = Color(0xFFD4D4D4);

  @override
  Widget build(BuildContext context) {
    final color = switch (line.priority) {
      LogPriority.fatal => _fatal,
      LogPriority.error => _error,
      LogPriority.warn => _warn,
      LogPriority.info => _info,
      LogPriority.debug => _debug,
      LogPriority.verbose => _verbose,
      LogPriority.unknown => line.isError ? _error : _plain,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: SelectableText(
        line.raw,
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
