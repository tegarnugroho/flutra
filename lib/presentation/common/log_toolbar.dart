import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/log/live_log_cubit.dart';
import '../../domain/entities/log_line.dart';
import 'compact_field.dart';
import 'outlined_action_button.dart';

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
        CompactField(
          width: 200,
          placeholder: state.useRegex ? 'Regex filter' : 'Search',
          onChanged: cubit.setQuery,
        ),
        ToggleChip(
          label: '.*',
          checked: state.useRegex,
          onChanged: cubit.setUseRegex,
        ),
        if (showTag)
          CompactField(
            width: 140,
            icon: FluentIcons.tag,
            placeholder: 'Tag filter',
            onChanged: cubit.setTagFilter,
          ),
        if (showPriority)
          CompactCombo<LogPriority>(
            width: 120,
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
                CompactComboItem(value: pr, label: '≥ ${pr.label}'),
            ],
            onChanged: cubit.setMinPriority,
          ),
        OutlinedActionButton(
          icon: state.paused ? FluentIcons.play : FluentIcons.pause,
          tooltip: state.paused ? 'Resume' : 'Pause',
          onPressed: state.paused ? cubit.resume : cubit.pause,
        ),
        OutlinedActionButton(
          icon: FluentIcons.clear,
          tooltip: 'Clear',
          onPressed: cubit.clear,
        ),
        OutlinedActionButton(
          icon: FluentIcons.save,
          tooltip: 'Save to file',
          onPressed: state.lines.isEmpty ? null : () => _save(context),
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
