import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../application/flutter_sdk/flutter_sdk_cubit.dart';
import '../../core/command/command_runner.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/flutter_sdk_info.dart';
import '../../infrastructure/trash/trash_entry.dart';
import '../common/busy_dialog.dart';
import '../common/command_progress_dialog.dart';
import '../common/copy_icon_button.dart';
import '../common/grouped_list.dart';
import '../common/outlined_action_button.dart';
import '../common/status_dot.dart';
import '../emulator/widgets/avd_dialogs.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Checks the SDK checkout before a git-backed command (upgrade, channel or
/// version switch), which Flutter refuses to run while the tree is dirty.
///
/// Returns `false` when the checkout is clean, `true` when the user agreed to
/// stash the local changes, and `null` when they cancelled.
Future<bool?> _resolveLocalChanges(BuildContext context) async {
  final cubit = context.read<FlutterSdkCubit>();
  var changes = const <String>[];
  await showBusyDialog(
    context,
    title: 'Checking the SDK checkout',
    message: 'Looking for local changes that would block the command.',
    task: () async => changes = await cubit.localChanges(),
  );
  if (changes.isEmpty) return false;
  if (!context.mounted) return null;

  const maxShown = 8;
  final preview = changes.take(maxShown).join('\n');
  final extra = changes.length - maxShown;
  final ok = await showConfirmDialog(
    context,
    title: 'The Flutter SDK has local changes',
    message: 'Flutter will not upgrade or switch while its checkout is dirty:'
        '\n\n$preview${extra > 0 ? '\n… and $extra more' : ''}\n\n'
        'Stash them and continue? They stay recoverable by running '
        '"git stash pop" in the SDK folder.',
    confirmLabel: 'Stash & continue',
    destructive: false,
  );
  return ok ? true : null;
}

/// Flutter SDK management: view the active SDK, switch channels and versions.
class FlutterSdkPage extends StatelessWidget {
  const FlutterSdkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FlutterSdkCubit>()..load(),
      child: const _FlutterSdkView(),
    );
  }
}

class _FlutterSdkView extends StatelessWidget {
  const _FlutterSdkView();

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: BlocConsumer<FlutterSdkCubit, FlutterSdkState>(
        listenWhen: (p, c) =>
            c.errorMessage != null && p.errorMessage != c.errorMessage,
        listener: (context, state) {
          displayInfoBar(context, builder: (context, close) {
            return InfoBar(
              title: const Text('Error'),
              content: Text(state.errorMessage!),
              severity: InfoBarSeverity.error,
              isLong: true,
              onClose: close,
            );
          });
        },
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    const Text('Flutter SDK', style: AppTextStyles.pageTitle),
                    const Spacer(),
                    _HeaderActions(state: state),
                  ],
                ),
              ),
              Expanded(child: _body(context, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, FlutterSdkState state) {
    final cubit = context.read<FlutterSdkCubit>();
    if (state.isLoading && state.info == null) {
      return const Center(child: ProgressRing());
    }
    if (state.status == FlutterSdkStatus.notInstalled) {
      return _InstallView(
        onInstalled: cubit.load,
        restorable: state.restorable,
        onRestore: cubit.restore,
      );
    }
    if (state.status == FlutterSdkStatus.failure && state.info == null) {
      return _ErrorView(
        message: state.errorMessage ?? 'Unknown error.',
        onRetry: cubit.load,
      );
    }
    final info = state.info;
    if (info == null) return const SizedBox.shrink();
    return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CurrentSdkCard(
                  info: info,
                  onAddToPath: info.sdkPath == null
                      ? null
                      : () => _addToPath(context, info.sdkPath!),
                ),
                if (!info.isKnownChannel) ...[
                  const SizedBox(height: 16),
                  InfoBar(
                    title: const Text('Off the official channel'),
                    content: Text(
                      'The SDK is on "${info.channel}" (a version checkout), so '
                      'flutter reports an unknown channel. Reset to stable to '
                      'return to an official channel and its latest build.',
                    ),
                    severity: InfoBarSeverity.warning,
                    isLong: true,
                    action: FilledButton(
                      onPressed: () => _run(
                        context,
                        'Resetting to stable channel',
                        (stash) => cubit.resetToStable(stashLocalChanges: stash),
                      ),
                      child: const Text('Reset to stable'),
                    ),
                  ),
                ],
                if (info.isGitRepo && !info.isStandardRemote) ...[
                  const SizedBox(height: 12),
                  InfoBar(
                    title: const Text('Non-standard upstream remote'),
                    content: Text(
                      'The SDK git remote is "${info.remoteUrl ?? 'unknown'}", '
                      'which triggers a "not a standard remote" warning in '
                      'Flutter Doctor. Point it at the official repository.',
                    ),
                    severity: InfoBarSeverity.warning,
                    isLong: true,
                    action: FilledButton(
                      onPressed: cubit.fixRemote,
                      child: const Text('Fix remote'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const SectionLabel('Channel'),
                const SizedBox(height: 4),
                const Text(
                  'Switch release channel, then Upgrade to fetch its latest '
                  'build.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 10),
                _ChannelSection(
                  current: info.channel,
                  browsing: state.browsingChannel ?? info.channel,
                ),
                const SizedBox(height: 22),
                _VersionsSection(state: state),
              ],
            ),
          );
  }

  /// Runs a streaming SDK command and reloads on success.
  /// Runs a git-backed SDK command, first clearing any local changes in the
  /// checkout that would make it fail. [start] receives whether those changes
  /// were stashed.
  static Future<void> _run(
    BuildContext context,
    String title,
    Future<RunningCommand> Function(bool stashLocalChanges) start,
  ) async {
    final cubit = context.read<FlutterSdkCubit>();
    final stash = await _resolveLocalChanges(context);
    if (stash == null || !context.mounted) return;
    final ok = await showCommandProgressDialog(context,
        title: title, start: () => start(stash));
    if (ok) cubit.load();
  }

  static Future<void> _uninstall(
    BuildContext context,
    String path,
    String version,
  ) async {
    final cubit = context.read<FlutterSdkCubit>();
    final ok = await showConfirmDialog(
      context,
      title: 'Uninstall Flutter $version',
      message: 'This permanently deletes the SDK folder:\n$path\n\nRemove its '
          '"\\bin" entry from PATH afterwards. This cannot be undone.',
      confirmLabel: 'Uninstall',
    );
    if (!ok || !context.mounted) return;
    await showBusyDialog(
      context,
      title: 'Uninstalling Flutter SDK',
      message: 'Removing $path …',
      task: cubit.uninstall,
    );
  }

  static Future<void> _addToPath(BuildContext context, String sdkPath) async {
    final cubit = context.read<FlutterSdkCubit>();
    try {
      await cubit.addToPath(sdkPath);
      if (!context.mounted) return;
      await displayInfoBar(context, builder: (context, close) {
        return InfoBar(
          title: const Text('Added to PATH'),
          content: const Text(
              'Open a NEW terminal (and restart this app) for "flutter" to be '
              'available. Existing terminals keep the old PATH.'),
          severity: InfoBarSeverity.success,
          isLong: true,
          onClose: close,
        );
      });
    } catch (e) {
      if (!context.mounted) return;
      await displayInfoBar(context, builder: (context, close) {
        return InfoBar(
          title: const Text('Could not update PATH'),
          content: Text('$e'),
          severity: InfoBarSeverity.error,
          isLong: true,
          onClose: close,
        );
      });
    }
  }
}

/// Page-header actions: Upgrade, Refresh and an overflow menu holding the
/// rarely-used (and destructive) commands.
class _HeaderActions extends StatefulWidget {
  const _HeaderActions({required this.state});

  final FlutterSdkState state;

  @override
  State<_HeaderActions> createState() => _HeaderActionsState();
}

class _HeaderActionsState extends State<_HeaderActions> {
  final _overflow = FlyoutController();

  @override
  void dispose() {
    _overflow.dispose();
    super.dispose();
  }

  void _showOverflow(BuildContext context) {
    final info = widget.state.info;
    _overflow.showFlyout(
      builder: (flyoutContext) => MenuFlyout(
        items: [
          if (info != null)
            MenuFlyoutItem(
              text: Text(
                'Git repo: ${info.isGitRepo ? 'yes' : 'no'}',
                style: AppTextStyles.inlineNote,
              ),
              // Diagnostic only — kept out of the card, not actionable here.
              onPressed: null,
            ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.delete,
                size: 14, color: AppColors.statusError),
            text: const Text('Uninstall this SDK',
                style: TextStyle(color: AppColors.statusError)),
            onPressed: info?.sdkPath == null
                ? null
                : () {
                    Navigator.of(flyoutContext).pop();
                    _FlutterSdkView._uninstall(
                        context, info!.sdkPath!, info.version);
                  },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FlutterSdkCubit>();
    final state = widget.state;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedActionButton(
          icon: FluentIcons.up,
          label: 'Upgrade',
          onPressed: state.info == null
              ? null
              : () => _FlutterSdkView._run(
                  context,
                  'Upgrading Flutter (${state.info!.channel})',
                  (stash) => cubit.upgrade(stashLocalChanges: stash)),
        ),
        const SizedBox(width: 8),
        OutlinedActionButton(
          icon: FluentIcons.refresh,
          label: 'Refresh',
          busy: state.isLoading,
          onPressed: cubit.load,
        ),
        const SizedBox(width: 8),
        FlyoutTarget(
          controller: _overflow,
          child: OutlinedActionButton(
            icon: FluentIcons.more,
            tooltip: 'More actions',
            onPressed: () => _showOverflow(context),
          ),
        ),
      ],
    );
  }
}

class _CurrentSdkCard extends StatelessWidget {
  const _CurrentSdkCard({required this.info, this.onAddToPath});

  /// Revisions are 40-char hashes; this is what git itself shows.
  static const _shortRevisionLength = 8;

  final FlutterSdkInfo info;
  final VoidCallback? onAddToPath;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final revision = info.frameworkRevision;
    return GroupedBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.developer_tools,
                  size: 18, color: palette.textSecondary),
              const SizedBox(width: 10),
              Text('Flutter ${info.version}', style: AppTextStyles.heroTitle),
              const SizedBox(width: 8),
              _ChannelBadge(channel: info.channel),
              const Spacer(),
              if (onAddToPath != null)
                OutlinedActionButton(
                  icon: FluentIcons.command_prompt,
                  label: 'Add to PATH',
                  tooltip:
                      'Add Flutter to PATH so "flutter" works in any terminal',
                  onPressed: onAddToPath,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (info.dartVersion != null)
                _meta(label: 'Dart', value: info.dartVersion!),
              if (revision != null)
                _meta(
                  label: 'Revision',
                  value: revision.length > _shortRevisionLength
                      ? revision.substring(0, _shortRevisionLength)
                      : revision,
                  copyValue: revision,
                  copyLabel: 'Revision',
                ),
              if (info.sdkPath != null)
                _meta(
                  value: info.sdkPath!,
                  copyValue: info.sdkPath!,
                  copyLabel: 'SDK path',
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// One metadata fragment: muted label, mono value, optional copy action.
  Widget _meta({
    String? label,
    required String value,
    String? copyValue,
    String? copyLabel,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label, style: AppTextStyles.rowSecondary),
          const SizedBox(width: 6),
        ],
        Text(value, style: AppTextStyles.monoValue),
        if (copyValue != null) ...[
          const SizedBox(width: 4),
          CopyIconButton(value: copyValue, label: copyLabel ?? 'Value'),
        ],
      ],
    );
  }
}

class _ChannelSection extends StatelessWidget {
  const _ChannelSection({required this.current, required this.browsing});

  /// The channel the SDK is actually on right now.
  final String current;

  /// The channel currently being browsed (drives the version list).
  final String browsing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final cubit = context.read<FlutterSdkCubit>();
    final pendingSwitch = browsing != current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final channel in kFlutterChannels)
              _ChannelChoice(
                channel: channel,
                selected: channel == browsing,
                onTap: () => cubit.browseChannel(channel),
              ),
          ],
        ),
        if (pendingSwitch) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(FluentIcons.info, size: 13, color: palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Browsing "$browsing". Your SDK is still on '
                  '"$current". Switch to apply.',
                  style: AppTextStyles.caption,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedActionButton(
                icon: FluentIcons.switch_widget,
                label: 'Switch to $browsing',
                onPressed: () => _switch(context, browsing),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _switch(BuildContext context, String channel) async {
    final cubit = context.read<FlutterSdkCubit>();
    final ok = await showConfirmDialog(
      context,
      title: 'Switch to $channel channel?',
      message: 'This changes the active Flutter channel. Run Upgrade afterwards '
          'to download its latest build.',
      confirmLabel: 'Switch',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    final stash = await _resolveLocalChanges(context);
    if (stash == null || !context.mounted) return;
    final done = await showCommandProgressDialog(
      context,
      title: 'Switching to $channel',
      start: () => cubit.switchChannel(channel, stashLocalChanges: stash),
    );
    if (done) cubit.load();
  }
}

/// A compact channel chip. The selected one carries the app's only accent.
class _ChannelChoice extends StatelessWidget {
  const _ChannelChoice({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final String channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? palette.accentBgTint : Colors.transparent,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: AppShape.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChannelChoiceDot(selected: selected),
              const SizedBox(width: 9),
              Text(
                channel,
                style: selected
                    ? AppTextStyles.rowTitle
                    : AppTextStyles.navItem,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filled accent dot when selected, hollow muted ring when not.
class _ChannelChoiceDot extends StatelessWidget {
  const _ChannelChoiceDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (selected) return StatusDot(color: palette.accent);
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.textMuted, width: AppShape.hairline),
      ),
    );
  }
}

class _VersionsSection extends StatefulWidget {
  const _VersionsSection({required this.state});

  final FlutterSdkState state;

  @override
  State<_VersionsSection> createState() => _VersionsSectionState();
}

class _VersionsSectionState extends State<_VersionsSection> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    if (!state.canSwitchVersion) {
      return InfoBar(
        title: const Text('Version switching unavailable'),
        content: const Text(
            'This Flutter SDK is not a git checkout, so specific versions '
            'cannot be selected. Use channels above.'),
        severity: InfoBarSeverity.info,
        isLong: true,
      );
    }

    final channel = state.browsingChannel ?? '';
    final versions = _query.isEmpty
        ? state.versions
        : state.versions
            .where((v) => v.contains(_query.trim()))
            .toList();
    final current = state.info?.version;

    // Bounded so the outer scroll view stays usable.
    final shown = versions.take(80).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SectionLabel('Versions · ${state.versions.length} available'),
            const SizedBox(width: 10),
            if (state.versionsLoading)
              const SizedBox(
                  width: 12, height: 12, child: ProgressRing(strokeWidth: 2)),
            const Spacer(),
            _VersionFilterBox(onChanged: (v) => setState(() => _query = v)),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Checks out a release tag in the SDK git repo. Commit or stash any '
          'local SDK changes first.',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: 10),
        if (versions.isEmpty && !state.versionsLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _query.isNotEmpty
                  ? 'No versions match "$_query".'
                  : 'No version tags found for the "$channel" channel. '
                      'Run "git fetch --tags" in the SDK folder to pull them.',
              style: AppTextStyles.caption,
            ),
          )
        else
          GroupedList(
            children: [
              for (final v in shown)
                _VersionTile(
                  version: v,
                  isCurrent: v == current,
                  onSwitch: () => _switch(context, v),
                  loadChangelog: () => context
                      .read<FlutterSdkCubit>()
                      .changelog(v, _previousOf(v, state.versions)),
                  onOpenGitHub: () =>
                      context.read<FlutterSdkCubit>().openReleasePage(v),
                ),
            ],
          ),
        if (versions.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing first ${shown.length} of ${versions.length}. Filter to '
              'narrow down.',
              style: AppTextStyles.caption,
            ),
          ),
      ],
    );
  }

  /// The next-older version in the sorted list, used as the changelog baseline.
  String? _previousOf(String version, List<String> all) {
    final i = all.indexOf(version);
    return (i >= 0 && i + 1 < all.length) ? all[i + 1] : null;
  }

  Future<void> _switch(BuildContext context, String version) async {
    final cubit = context.read<FlutterSdkCubit>();
    final ok = await showConfirmDialog(
      context,
      title: 'Switch to Flutter $version?',
      message: 'This checks out tag $version in the Flutter SDK git repo and '
          'rebuilds the tool. It changes your global Flutter version.',
      confirmLabel: 'Switch',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    final stash = await _resolveLocalChanges(context);
    if (stash == null || !context.mounted) return;
    final done = await showCommandProgressDialog(
      context,
      title: 'Switching to Flutter $version',
      start: () => cubit.switchVersion(version, stashLocalChanges: stash),
    );
    if (done) cubit.load();
  }
}

class _VersionTile extends StatefulWidget {
  const _VersionTile({
    required this.version,
    required this.isCurrent,
    required this.onSwitch,
    required this.loadChangelog,
    required this.onOpenGitHub,
  });

  final String version;
  final bool isCurrent;
  final VoidCallback onSwitch;
  final Future<List<String>> Function() loadChangelog;
  final VoidCallback onOpenGitHub;

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  bool _expanded = false;
  bool _loading = false;
  bool _hovered = false;
  bool _focused = false;
  List<String>? _lines;

  /// Row actions stay hidden until the row is pointed at or focused, so the
  /// list doesn't become a wall of identical buttons.
  bool get _showActions => _hovered || _focused;

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _lines == null && !_loading) {
      setState(() => _loading = true);
      try {
        final lines = await widget.loadChangelog();
        if (mounted) setState(() => _lines = lines);
      } catch (_) {
        if (mounted) setState(() => _lines = const []);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _toggle();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          color: _hovered ? palette.surfaceRaised : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Column(
            children: [
              Row(
                children: [
                  // Fixed slot so every version number starts on the same x.
                  StatusDot(
                      color: widget.isCurrent ? palette.statusOk : null),
                  const SizedBox(width: 10),
                  Text(
                    widget.version,
                    style: widget.isCurrent
                        ? AppTextStyles.monoRowActive
                        : AppTextStyles.monoRow,
                  ),
                  if (widget.isCurrent) ...[
                    const SizedBox(width: 8),
                    const Text('current', style: AppTextStyles.inlineNote),
                  ],
                  const Spacer(),
                  if (_showActions) ...[
                    OutlinedActionButton(
                      icon: FluentIcons.globe,
                      dense: true,
                      tooltip: 'Open release notes on GitHub',
                      onPressed: widget.onOpenGitHub,
                    ),
                    const SizedBox(width: 8),
                    if (!widget.isCurrent) ...[
                      OutlinedActionButton(
                        icon: FluentIcons.switch_widget,
                        label: 'Switch',
                        dense: true,
                        onPressed: widget.onSwitch,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(FluentIcons.chevron_down,
                        size: 13, color: palette.textMuted),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10, left: 16),
                        child: _changelog(palette),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _changelog(AppPalette palette) {
    if (_loading) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
              width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
        ),
      );
    }
    final lines = _lines ?? const [];
    if (lines.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No changelog available from the local git history. Use the GitHub '
          'link for full release notes.',
          style: AppTextStyles.caption,
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.border, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${lines.length} commits since previous version',
              style: AppTextStyles.rowSecondary),
          const SizedBox(height: 4),
          for (final line in lines.take(200))
            Text(line, style: AppTextStyles.monoBody),
        ],
      ),
    );
  }
}

/// The channel as a quiet outline pill — no fill, no per-channel colour.
class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.channel});

  final String channel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: palette.borderStrong, width: AppShape.hairline),
      ),
      child: Text(channel, style: AppTextStyles.badge),
    );
  }
}

/// Compact search box for the versions list.
class _VersionFilterBox extends StatelessWidget {
  const _VersionFilterBox({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: 200,
      height: 30,
      child: TextBox(
        placeholder: 'Filter versions',
        style: AppTextStyles.input,
        placeholderStyle: AppTextStyles.input.copyWith(color: palette.textMuted),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        prefix: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(FluentIcons.search, size: 12, color: palette.textMuted),
        ),
        decoration: WidgetStateProperty.all(
          BoxDecoration(
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
            border:
                Border.all(color: palette.border, width: AppShape.hairline),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Shown when no Flutter SDK is on PATH: clone one into a chosen folder.
class _InstallView extends StatefulWidget {
  const _InstallView({
    required this.onInstalled,
    this.restorable = const [],
    required this.onRestore,
  });

  final VoidCallback onInstalled;
  final List<TrashEntry> restorable;
  final ValueChanged<TrashEntry> onRestore;

  @override
  State<_InstallView> createState() => _InstallViewState();
}

class _InstallViewState extends State<_InstallView> {
  // Sentinel meaning "the channel tip" rather than a specific version tag.
  static const _latest = '__latest__';

  late final TextEditingController _dir;
  String _channel = 'stable';
  String _version = _latest;
  List<String> _versions = const [];
  bool _loadingVersions = false;

  @override
  void initState() {
    super.initState();
    _dir = TextEditingController(text: r'C:\Dev\SDK\flutter');
    _loadVersions();
  }

  @override
  void dispose() {
    _dir.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    setState(() => _loadingVersions = true);
    final versions =
        await context.read<FlutterSdkCubit>().listInstallableVersions(_channel);
    if (!mounted) return;
    setState(() {
      _versions = versions;
      _version = _latest; // reset selection when channel changes
      _loadingVersions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.restorable.isNotEmpty) ...[
              InfoBar(
                title: const Text('Recently uninstalled'),
                content: Text(
                    'You uninstalled a Flutter SDK. It is kept for 24 hours — '
                    'restore it to ${widget.restorable.first.originalPath}.'),
                severity: InfoBarSeverity.warning,
                isLong: true,
                action: FilledButton(
                  onPressed: () =>
                      widget.onRestore(widget.restorable.first),
                  child: const Text('Restore'),
                ),
              ),
              const SizedBox(height: 18),
            ],
            Icon(FluentIcons.download,
                size: 24, color: AppPalette.of(context).textSecondary),
            const SizedBox(height: 14),
            const Text('No Flutter SDK found',
                textAlign: TextAlign.center, style: AppTextStyles.heroTitle),
            const SizedBox(height: 8),
            Text(
              'Flutter is not on your PATH. Clone the SDK from GitHub into a '
              'folder below (git is required).',
              textAlign: TextAlign.center,
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
            const SizedBox(height: 22),
            InfoLabel(
              label: 'Install folder',
              child: TextBox(controller: _dir),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InfoLabel(
                    label: 'Channel',
                    child: ComboBox<String>(
                      isExpanded: true,
                      value: _channel,
                      items: [
                        for (final c in kFlutterChannels)
                          ComboBoxItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _channel = v);
                        _loadVersions();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: 'Version',
                    child: _loadingVersions
                        ? const SizedBox(
                            height: 32,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: ProgressRing(strokeWidth: 2)),
                            ),
                          )
                        : ComboBox<String>(
                            isExpanded: true,
                            value: _version,
                            items: [
                              const ComboBoxItem(
                                  value: _latest,
                                  child: Text('Latest (channel tip)')),
                              for (final v in _versions)
                                ComboBoxItem(value: v, child: Text(v)),
                            ],
                            onChanged: (v) =>
                                setState(() => _version = v ?? _latest),
                          ),
                  ),
                ),
              ],
            ),
            if (!_loadingVersions && _versions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Could not fetch the version list (offline?). "Latest" still '
                  'works.',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorTertiary,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _install,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.download, size: 14),
                    SizedBox(width: 8),
                    Text('Install Flutter'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _install() async {
    final cubit = context.read<FlutterSdkCubit>();
    final dir = _dir.text.trim();
    final ref = _version == _latest ? _channel : _version;
    final ok = await showCommandProgressDialog(
      context,
      title: 'Cloning Flutter ($ref)',
      start: () => cubit.installSdk(dir, ref),
    );
    if (!ok || !mounted) return;
    // Offer to wire the new SDK into PATH.
    final addPath = await showConfirmDialog(
      context,
      title: 'Add Flutter to PATH?',
      message: 'Append "${p.join(dir, 'bin')}" to your user PATH so "flutter" '
          'works everywhere. You must restart this app (and open terminals) '
          'for it to take effect.',
      confirmLabel: 'Add to PATH',
      destructive: false,
    );
    if (addPath && mounted) {
      try {
        await cubit.addToPath(dir);
        if (mounted) {
          await displayInfoBar(context, builder: (context, close) {
            return InfoBar(
              title: const Text('Added to PATH'),
              content: const Text(
                  'Restart the app to detect the new Flutter SDK.'),
              severity: InfoBarSeverity.success,
              onClose: close,
            );
          });
        }
      } catch (e) {
        if (mounted) {
          await displayInfoBar(context, builder: (context, close) {
            return InfoBar(
              title: const Text('Could not update PATH'),
              content: Text('$e'),
              severity: InfoBarSeverity.warning,
              onClose: close,
            );
          });
        }
      }
    }
    widget.onInstalled();
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.error_badge,
                size: 24, color: AppColors.statusError),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: AppTextStyles.statusLine),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
