import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

import '../../application/common/command_log_cubit.dart';
import '../../core/command/command_result.dart';

/// A terminal-style, auto-scrolling view of a streaming command's output.
class CommandLogView extends StatelessWidget {
  const CommandLogView({super.key, this.height = 320});

  final double height;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CommandLogCubit, CommandLogState>(
      builder: (context, state) => LogLinesView(
        lines: state.lines,
        height: height,
        starting: state.lines.isEmpty && state.running,
      ),
    );
  }
}

/// The log box itself, for callers that hold their own lines rather than a
/// [CommandLogCubit] — the version switch runs several processes into one view.
class LogLinesView extends StatefulWidget {
  const LogLinesView({
    super.key,
    required this.lines,
    this.height = 320,
    this.starting = false,
  });

  final List<CommandOutputLine> lines;
  final double height;

  /// Shows the "Starting…" placeholder while there is nothing to print yet.
  final bool starting;

  @override
  State<LogLinesView> createState() => _LogLinesViewState();
}

class _LogLinesViewState extends State<LogLinesView> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: widget.height,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.logBg,
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
        border: Border.all(color: palette.border, width: AppShape.hairline),
      ),
      child: Builder(
        builder: (context) {
          _autoScroll();
          if (widget.lines.isEmpty && widget.starting) {
            return Center(
              child: Text(
                'Starting…',
                style: AppTextStyles.of(context).caption,
              ),
            );
          }
          return ListView.builder(
            controller: _scroll,
            itemCount: widget.lines.length,
            itemBuilder: (context, i) {
              final line = widget.lines[i];
              return Text(
                line.text,
                style: AppTextStyles.of(context).monoLog.copyWith(
                  color: line.isError
                      ? palette.statusError
                      : palette.textSecondary,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
