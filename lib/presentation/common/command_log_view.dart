import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

import '../../application/common/command_log_cubit.dart';

/// A terminal-style, auto-scrolling view of a streaming command's output.
class CommandLogView extends StatefulWidget {
  const CommandLogView({super.key, this.height = 320});

  final double height;

  @override
  State<CommandLogView> createState() => _CommandLogViewState();
}

class _CommandLogViewState extends State<CommandLogView> {
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
      child: BlocBuilder<CommandLogCubit, CommandLogState>(
        builder: (context, state) {
          _autoScroll();
          if (state.lines.isEmpty && state.running) {
            return Center(
              child: Text(
                'Starting…',
                style: AppTextStyles.of(context).caption,
              ),
            );
          }
          return ListView.builder(
            controller: _scroll,
            itemCount: state.lines.length,
            itemBuilder: (context, i) {
              final line = state.lines[i];
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
