import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/log/live_log_cubit.dart';
import '../../domain/entities/log_line.dart';

/// Shared Pause / Clear / Save / search controls for a [LiveLogCubit] stream.
class LogToolbar extends StatelessWidget {
  const LogToolbar({
    super.key,
    required this.cubit,
    required this.state,
    this.showPriority = false,
    this.showTag = false,
    this.savePrefix = 'log',
  });

  final LiveLogCubit cubit;
  final LiveLogState state;
  final bool showPriority;
  final bool showTag;
  final String savePrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextBox(
            placeholder: state.useRegex ? 'Regex filter…' : 'Search…',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.search, size: 14),
            ),
            onChanged: cubit.setQuery,
          ),
        ),
        ToggleButton(
          checked: state.useRegex,
          onChanged: cubit.setUseRegex,
          child: const Text('.*'),
        ),
        if (showTag)
          SizedBox(
            width: 150,
            child: TextBox(
              placeholder: 'Tag filter…',
              onChanged: cubit.setTagFilter,
            ),
          ),
        if (showPriority)
          SizedBox(
            width: 130,
            child: ComboBox<LogPriority>(
              isExpanded: true,
              value: state.minPriority,
              items: [
                for (final pr in const [
                  LogPriority.verbose,
                  LogPriority.debug,
                  LogPriority.info,
                  LogPriority.warn,
                  LogPriority.error,
                  LogPriority.fatal,
                ])
                  ComboBoxItem(value: pr, child: Text('≥ ${pr.label}')),
              ],
              onChanged: (v) => v == null ? null : cubit.setMinPriority(v),
            ),
          ),
        Tooltip(
          message: state.paused ? 'Resume' : 'Pause',
          child: IconButton(
            icon: Icon(state.paused ? FluentIcons.play : FluentIcons.pause),
            onPressed: state.paused ? cubit.resume : cubit.pause,
          ),
        ),
        Tooltip(
          message: 'Clear',
          child: IconButton(
            icon: const Icon(FluentIcons.clear),
            onPressed: cubit.clear,
          ),
        ),
        Tooltip(
          message: 'Save to file',
          child: IconButton(
            icon: const Icon(FluentIcons.save),
            onPressed: state.lines.isEmpty ? null : () => _save(context),
          ),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    try {
      Directory? base;
      try {
        base = await getDownloadsDirectory();
      } catch (_) {
        base = null;
      }
      base ??= await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'AndroidSdkManager', 'logs'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(p.join(dir.path, '${savePrefix}_$stamp.txt'));
      // Save what's currently visible (filtered) so exports match the view.
      await file.writeAsString(state.filtered.map((l) => l.raw).join('\n'));
      if (!context.mounted) return;
      await displayInfoBar(context, builder: (context, close) {
        return InfoBar(
          title: const Text('Log saved'),
          content: Text(file.path),
          severity: InfoBarSeverity.success,
          isLong: true,
          onClose: close,
        );
      });
    } catch (e) {
      if (!context.mounted) return;
      await displayInfoBar(context, builder: (context, close) {
        return InfoBar(
          title: const Text('Could not save log'),
          content: Text('$e'),
          severity: InfoBarSeverity.error,
          onClose: close,
        );
      });
    }
  }
}
