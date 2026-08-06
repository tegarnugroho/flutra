import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/doctor/doctor_fix_cubit.dart';
import '../../../domain/entities/doctor_issue.dart';
import '../../../infrastructure/doctor/doctor_fix_service.dart';
import '../../common/app_loader.dart';
import '../../common/command_log_view.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// How long a successful fix stays on screen before the dialog closes itself.
const Duration kFixAutoCloseDelay = Duration(milliseconds: 1500);

/// Confirms a fix, runs it, and shows its output.
///
/// What the dialog left behind, read before the cubit is reset.
class FixDialogResult {
  const FixDialogResult({
    this.succeeded = false,
    this.rerun = false,
    this.restartRequired = false,
    this.blocksRerun = false,
    this.note,
  });

  final bool succeeded;

  /// The page should re-run doctor now.
  final bool rerun;

  /// The change only reaches processes started later.
  final bool restartRequired;

  /// Something outside the app is still running.
  final bool blocksRerun;

  final String? note;
}

/// Confirms a fix, runs it, shows its output, and reports what happened.
Future<FixDialogResult> showDoctorFixDialog(
  BuildContext context, {
  required DoctorIssue issue,
  required DoctorFixCubit cubit,
}) async {
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _DoctorFixDialog(issue: issue),
    ),
  );
  // Read before the reset below wipes it — the page needs the verdict to
  // decide between re-running doctor and raising the restart banner.
  final state = cubit.state;
  final result = FixDialogResult(
    succeeded: state.succeeded,
    rerun: state.shouldRerun,
    restartRequired: state.needsRestart,
    blocksRerun: state.blocksRerun,
    note: state.outcome?.note,
  );
  cubit.reset();
  return result;
}

class _DoctorFixDialog extends StatefulWidget {
  const _DoctorFixDialog({required this.issue});

  final DoctorIssue issue;

  @override
  State<_DoctorFixDialog> createState() => _DoctorFixDialogState();
}

class _DoctorFixDialogState extends State<_DoctorFixDialog> {
  List<FixChoice>? _options;
  String? _choice;
  bool _loadingOptions = false;

  bool get _isGuided => widget.issue.kind == FixKind.guided;

  @override
  void initState() {
    super.initState();
    if (_isGuided) _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() => _loadingOptions = true);
    final options = await context.read<DoctorFixCubit>().optionsFor(widget.issue);
    if (!mounted) return;
    setState(() {
      _options = options;
      // Pre-select the first hit: it is nearly always the right one, and the
      // list is ordered best-first.
      _choice = options.isEmpty ? null : options.first.value;
      _loadingOptions = false;
    });
  }

  Future<void> _browse() async {
    // The browser fix picks an executable; the SDK/JDK ones pick a folder.
    final path = widget.issue.id == 'chrome_missing'
        ? (await openFile(acceptedTypeGroups: const [
            XTypeGroup(label: 'Programs', extensions: ['exe']),
          ]))
            ?.path
        : await getDirectoryPath(confirmButtonText: 'Select');
    if (path == null || !mounted) return;
    setState(() {
      _options = [
        ...?_options,
        FixChoice(value: path, label: path, detail: 'Chosen by hand'),
      ];
      _choice = path;
    });
  }

  Future<void> _run() async {
    final cubit = context.read<DoctorFixCubit>();
    await cubit.run(widget.issue, choice: _choice);
    if (!mounted) return;
    final state = cubit.state;
    if (state.succeeded && !state.needsRestart && !state.blocksRerun) {
      // Nothing more to read on a clean run — get out of the way.
      await Future<void>.delayed(kFixAutoCloseDelay);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DoctorFixCubit, DoctorFixState>(
      builder: (context, state) {
        final running = state.isRunning;
        final finished = state.isFinished;
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 620),
          title: _Title(issue: widget.issue, state: state),
          content: finished || running
              ? _ExecutionPhase(state: state)
              : _ConfirmPhase(
                  issue: widget.issue,
                  options: _options,
                  choice: _choice,
                  loading: _loadingOptions,
                  onPick: (value) => setState(() => _choice = value),
                  onBrowse: _browse,
                ),
          actions: [
            if (!running && !finished) ...[
              Button(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _canRun ? _run : null,
                child: const Text('Run'),
              ),
            ] else if (finished)
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(state.shouldRerun),
                child: const Text('Close'),
              ),
          ],
        );
      },
    );
  }

  /// A guided fix with nothing chosen cannot run; an automatic one always can.
  bool get _canRun => !_loadingOptions && (!_isGuided || _choice != null);
}

class _Title extends StatelessWidget {
  const _Title({required this.issue, required this.state});

  final DoctorIssue issue;
  final DoctorFixState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Expanded(child: Text(issue.title)),
        if (state.isRunning)
          AppLoader(size: AppLoaderSize.small)
        else if (state.isFinished)
          Icon(
            state.succeeded
                ? FluentIcons.completed_solid
                : FluentIcons.error_badge,
            color: state.succeeded ? palette.statusOk : palette.statusError,
          ),
      ],
    );
  }
}

/// What the fix will do, and anything it needs answered first.
class _ConfirmPhase extends StatelessWidget {
  const _ConfirmPhase({
    required this.issue,
    required this.options,
    required this.choice,
    required this.loading,
    required this.onPick,
    required this.onBrowse,
  });

  final DoctorIssue issue;
  final List<FixChoice>? options;
  final String? choice;
  final bool loading;
  final ValueChanged<String> onPick;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final palette = AppPalette.of(context);
    final commands = context.read<DoctorFixCubit>().previewFor(
          issue,
          choice: choice,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(issue.description, style: text.caption),
        if (issue.kind == FixKind.guided) ...[
          const SizedBox(height: 14),
          if (loading)
            Row(
              children: [
                AppLoader(size: AppLoaderSize.small),
                const SizedBox(width: 10),
                Text('Looking…', style: text.caption),
              ],
            )
          else ...[
            if (options?.isEmpty ?? true)
              Text(
                'Nothing was found automatically — point at it yourself.',
                style: text.caption.copyWith(color: palette.statusWarn),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final option in options!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _OptionTile(
                            option: option,
                            selected: option.value == choice,
                            onTap: () => onPick(option.value),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Button(onPressed: onBrowse, child: const Text('Browse…')),
          ],
        ],
        if (commands.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Runs', style: text.rowLabel),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.logBg,
              borderRadius: BorderRadius.circular(AppShape.radiusControl),
              border: Border.all(color: palette.border, width: AppShape.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final command in commands)
                  Text(command, style: text.monoLog),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One selectable option. A tile rather than a radio button: it matches the
/// scan picker in Settings, and the two lists do the same job.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final FixChoice option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? palette.accentBgTint : palette.sidebarBg,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: AppShape.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? FluentIcons.radio_btn_on
                    : FluentIcons.radio_btn_off,
                size: 13,
                color: selected ? palette.accent : palette.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: text.rowTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (option.detail != null)
                      Text(
                        option.detail!,
                        style: text.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live output, then the verdict.
class _ExecutionPhase extends StatelessWidget {
  const _ExecutionPhase({required this.state});

  final DoctorFixState state;

  @override
  Widget build(BuildContext context) {
    final note = state.outcome?.note;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LogLinesView(
          lines: state.lines,
          height: 240,
          starting: state.isRunning,
        ),
        if (state.isFinished && note != null) ...[
          const SizedBox(height: 12),
          InfoBar(
            title: Text(state.succeeded ? 'Done' : 'Did not work'),
            content: Text(note),
            severity: state.succeeded
                ? (state.needsRestart || state.blocksRerun
                    ? InfoBarSeverity.warning
                    : InfoBarSeverity.success)
                : InfoBarSeverity.error,
            isLong: true,
          ),
        ],
      ],
    );
  }
}
