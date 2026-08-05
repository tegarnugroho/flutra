import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/entities/log_line.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'outlined_action_button.dart';

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
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.sidebarBg,
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
        border: Border.all(color: palette.border, width: AppShape.hairline),
      ),
      child: Stack(
        children: [
          if (widget.lines.isEmpty)
            Center(
              child: Text(
                widget.emptyHint ?? 'Waiting for output…',
                style: AppTextStyles.of(context).caption,
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
              child: OutlinedActionButton(
                icon: FluentIcons.down,
                label: 'Jump to end',
                dense: true,
                onPressed: () {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  setState(() => _stickToBottom = true);
                },
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

  /// Levels are the app's one multi-colour surface, and they stay muted:
  /// only warnings and errors get a semantic colour.
  static Color _colorFor(LogPriority priority, bool isError, AppPalette p) =>
      switch (priority) {
        LogPriority.fatal || LogPriority.error => p.statusError,
        LogPriority.warn => p.statusWarn,
        LogPriority.info => p.textSecondary,
        LogPriority.debug || LogPriority.verbose => p.textMuted,
        LogPriority.unknown => isError ? p.statusError : p.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SelectableText(
      line.raw,
      style: AppTextStyles.of(context).monoLog.copyWith(
        color: _colorFor(line.priority, line.isError, palette),
      ),
    );
  }
}
