import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../application/flutter_sdk/flutter_sdk_cubit.dart';
import '../../core/command/command_runner.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/flutter_release.dart';
import '../../domain/entities/flutter_sdk_info.dart';
import '../../domain/entities/version_switch.dart';
import '../../infrastructure/trash/trash_entry.dart';
import '../common/app_badge.dart';
import '../common/app_loader.dart';
import '../common/busy_dialog.dart';
import '../common/command_progress_dialog.dart';
import '../common/compact_field.dart';
import '../common/confirm_dialog.dart';
import '../common/copy_icon_button.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../common/status_dot.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'version_switch_dialog.dart';

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
    message:
        'Flutter will not upgrade or switch while its checkout is dirty:'
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
    return BlocConsumer<FlutterSdkCubit, FlutterSdkState>(
      listenWhen: (p, c) =>
          c.errorMessage != null && p.errorMessage != c.errorMessage,
      listener: (context, state) {
        displayInfoBar(
          context,
          builder: (context, close) {
            return InfoBar(
              title: const Text('Error'),
              content: Text(state.errorMessage!),
              severity: InfoBarSeverity.error,
              isLong: true,
              onClose: close,
            );
          },
        );
      },
      builder: (context, state) {
        return PageScaffold(
          title: 'Flutter SDK',
          actions: [_HeaderActions(state: state)],
          child: _body(context, state),
        );
      },
    );
  }

  Widget _body(BuildContext context, FlutterSdkState state) {
    return LoadingSwitcher(
      showSkeleton: state.isFirstLoad,
      skeleton: const FlutterSdkSkeleton(),
      builder: (context) => _loaded(context, state),
    );
  }

  Widget _loaded(BuildContext context, FlutterSdkState state) {
    final cubit = context.read<FlutterSdkCubit>();
    if (state.status == FlutterSdkStatus.notInstalled) {
      return _InstallView(
        onInstalled: cubit.load,
        restorable: state.restorable,
        onRestore: cubit.restore,
      );
    }
    if (state.status == FlutterSdkStatus.failure && state.info == null) {
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Could not read the Flutter SDK',
        message: state.errorMessage ?? 'Unknown error.',
        actionLabel: 'Retry',
        onAction: cubit.load,
      );
    }
    final info = state.info;
    if (info == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.updateAvailable) ...[
                _UpdateLine(state: state),
                const SizedBox(height: 12),
              ],
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
                    'The SDK is on "${info.channel}", which is not a release '
                    'channel, so flutter reports an unknown channel. Switching '
                    'a version here never causes this — it means the checkout '
                    'was moved outside the app. Reset to stable to return to '
                    'an official channel and its latest build.',
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
              Text(
                'Switch release channel, then Upgrade to fetch its latest '
                'build.',
                style: AppTextStyles.of(context).caption,
              ),
              const SizedBox(height: 10),
              _ChannelSection(
                current: info.channel,
                browsing: state.browsingChannel ?? info.channel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        // Only the version list scrolls; the SDK card and channel picker
        // stay put.
        Expanded(child: _VersionsSection(state: state)),
      ],
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
    final ok = await showCommandProgressDialog(
      context,
      title: title,
      start: () => start(stash),
    );
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
      message:
          'This permanently deletes the SDK folder:\n$path\n\nRemove its '
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
      await displayInfoBar(
        context,
        builder: (context, close) {
          return InfoBar(
            title: const Text('Added to PATH'),
            content: const Text(
              'Open a NEW terminal (and restart this app) for "flutter" to be '
              'available. Existing terminals keep the old PATH.',
            ),
            severity: InfoBarSeverity.success,
            isLong: true,
            onClose: close,
          );
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      await displayInfoBar(
        context,
        builder: (context, close) {
          return InfoBar(
            title: const Text('Could not update PATH'),
            content: Text('$e'),
            severity: InfoBarSeverity.error,
            isLong: true,
            onClose: close,
          );
        },
      );
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
                style: AppTextStyles.of(context).inlineNote,
              ),
              // Diagnostic only — kept out of the card, not actionable here.
              onPressed: null,
            ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            leading: Icon(
              FluentIcons.delete,
              size: 14,
              color: AppPalette.of(context).statusError,
            ),
            text: Text(
              'Uninstall this SDK',
              style: TextStyle(color: AppPalette.of(context).statusError),
            ),
            onPressed: info?.sdkPath == null
                ? null
                : () {
                    Navigator.of(flyoutContext).pop();
                    _FlutterSdkView._uninstall(
                      context,
                      info!.sdkPath!,
                      info.version,
                    );
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
                  (stash) => cubit.upgrade(stashLocalChanges: stash),
                ),
        ),
        const SizedBox(width: 8),
        OutlinedActionButton(
          icon: FluentIcons.refresh,
          label: 'Refresh',
          busy: state.isLoading,
          // Refresh always re-downloads the release index.
          onPressed: () => cubit.load(forceRefresh: true),
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

/// "You are behind the channel tip", driven by the release index's
/// `current_release` hash rather than a version-string comparison.
class _UpdateLine extends StatelessWidget {
  const _UpdateLine({required this.state});

  final FlutterSdkState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final latest = state.latestRelease;
    return StatusLine(
      color: palette.statusWarn,
      message: latest == null
          ? 'An update is available on this channel'
          : 'Flutter ${latest.displayVersion} is available on '
                '${state.info?.channel ?? latest.channel} — use Upgrade',
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
              Icon(
                FluentIcons.developer_tools,
                size: 18,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                'Flutter ${info.version}',
                style: AppTextStyles.of(context).heroTitle,
              ),
              const SizedBox(width: 8),
              AppBadge(info.channel),
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
                _meta(context, label: 'Dart', value: info.dartVersion!),
              if (revision != null)
                _meta(context, 
                  label: 'Revision',
                  value: revision.length > _shortRevisionLength
                      ? revision.substring(0, _shortRevisionLength)
                      : revision,
                  copyValue: revision,
                  copyLabel: 'Revision',
                ),
              if (info.sdkPath != null)
                _meta(context, 
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
  Widget _meta(
    BuildContext context, {
    String? label,
    required String value,
    String? copyValue,
    String? copyLabel,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label, style: AppTextStyles.of(context).rowSecondary),
          const SizedBox(width: 6),
        ],
        Text(value, style: AppTextStyles.of(context).monoValue),
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
                  style: AppTextStyles.of(context).caption,
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
      message:
          'This changes the active Flutter channel. Run Upgrade afterwards '
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
                    ? AppTextStyles.of(context).rowTitle
                    : AppTextStyles.of(context).navItem,
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
  final _scroll = ScrollController();
  String _query = '';

  @override
  void didUpdateWidget(covariant _VersionsSection old) {
    super.didUpdateWidget(old);
    // A different channel is a different list — start it at the top.
    if (old.state.browsingChannel != widget.state.browsingChannel &&
        _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    if (!state.canSwitchVersion) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: InfoBar(
          title: Text('Version switching unavailable'),
          content: Text(
            'This Flutter SDK is not a git checkout, so specific versions '
            'cannot be selected. Use channels above.',
          ),
          severity: InfoBarSeverity.info,
          isLong: true,
        ),
      );
    }

    final channel = state.browsingChannel ?? '';
    // master is a rolling branch: the release index publishes no versioned
    // entries for it, so there is nothing to list.
    if (channel == 'master') {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel('Versions'),
            SizedBox(height: 6),
            Text(
              'master is a rolling branch with no versioned releases. Switch '
              'to it above, then use Upgrade to move to its tip.',
              style: AppTextStyles.of(context).caption,
            ),
          ],
        ),
      );
    }
    final query = _query.trim();
    // Every release the official index publishes is listed — for stable that
    // reaches back to v1.0.0, same as the archive on the Flutter site. The list
    // is lazy, so length costs nothing.
    final shown = query.isEmpty
        ? state.releases
        : state.releases
              .where((r) => r.displayVersion.contains(query))
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SectionLabel('Versions', meta: '${shown.length} available'),
                  const SizedBox(width: 10),
                  if (state.versionsLoading)
                    AppLoader(size: AppLoaderSize.small),
                  const Spacer(),
                  CompactField(
                    width: 200,
                    placeholder: 'Filter versions',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _sourceCaption(state),
                style: AppTextStyles.of(context).caption,
              ),
              if (state.isUnlistedCommit) ...[
                const SizedBox(height: 4),
                Text(
                  'Local SDK is on an unlisted commit ${state.shortHeadHash} — '
                  'no row is marked current.',
                  style: AppTextStyles.of(context).caption,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: shown.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      query.isNotEmpty
                          ? 'No versions match "$query".'
                          : state.versionsLoading
                          ? 'Loading releases…'
                          : 'No releases found for the "$channel" channel.',
                      style: AppTextStyles.of(context).caption,
                    ),
                  )
                : GroupedListView(
                    controller: _scroll,
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _VersionTile(
                      // Keyed by release identity so a row's expanded state and
                      // loaded changelog follow the release, not its position —
                      // otherwise switching channel leaves whatever row sat at
                      // that index expanded.
                      key: ValueKey(
                        '${shown[i].channel}/${shown[i].version}/'
                        '${shown[i].hash}',
                      ),
                      release: shown[i],
                      isCurrent: _isCurrent(state, shown[i]),
                      onSwitch: () => _switch(context, shown[i]),
                      loadChangelog: () => context
                          .read<FlutterSdkCubit>()
                          .changelog(shown[i].gitTag, _previousOf(i, shown)),
                      onOpenGitHub: () => context
                          .read<FlutterSdkCubit>()
                          .openReleasePage(shown[i].gitTag),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// The current row is decided by commit, not version string — a re-released
  /// version shares its number with an older build.
  ///
  /// The git-tag fallback list knows no hashes, so those rows fall back to the
  /// version `flutter --version` reports.
  static bool _isCurrent(FlutterSdkState state, FlutterRelease release) {
    final head = state.headHash;
    if (release.hash.isEmpty || head == null || head.isEmpty) {
      final installed = state.info?.version;
      return installed != null && installed == release.displayVersion;
    }
    return release.hash == head;
  }

  static String _sourceCaption(FlutterSdkState state) =>
      switch (state.versionSource) {
        VersionSource.releaseIndex =>
          'Official Flutter releases. Switching checks the release tag out '
              'onto its channel branch, so the SDK stays on stable or beta.',
        VersionSource.staleCache =>
          'Offline — showing the cached release list. Press Refresh to retry.',
        VersionSource.gitTags =>
          'Offline — showing release tags from the local git checkout.',
      };

  /// The next-older release in the list, used as the changelog baseline.
  String? _previousOf(int index, List<FlutterRelease> all) =>
      index + 1 < all.length ? all[index + 1].gitTag : null;

  /// Switches the SDK to [release], on the channel branch the release index
  /// says it belongs to.
  Future<void> _switch(BuildContext context, FlutterRelease release) async {
    final cubit = context.read<FlutterSdkCubit>();
    final version = release.gitTag;
    final channel = switchChannelFor(release);
    if (channel == null) {
      await _notify(
        context,
        title: 'Cannot switch to $version',
        message:
            'This release is published on the "${release.channel}" channel, '
            'which has no branch to switch to. Use the channel picker instead.',
        severity: InfoBarSeverity.warning,
      );
      return;
    }

    // Nothing to do when the SDK already sits on this tag *and* on the channel
    // branch — a same-commit switch would only rebuild the tool cache.
    if (await cubit.isOnVersion(version, channel)) {
      if (!context.mounted) return;
      await _notify(
        context,
        title: 'Already on Flutter $version',
        message: 'The SDK is on this release, on the "$channel" channel.',
        severity: InfoBarSeverity.info,
      );
      return;
    }
    if (!context.mounted) return;

    final ok = await showConfirmDialog(
      context,
      title: 'Switch to Flutter $version?',
      message:
          'This checks out tag $version onto the "$channel" branch of the '
          'Flutter SDK and rebuilds the tool, so Flutter keeps reporting the '
          '"$channel" channel. It changes your global Flutter version. Any '
          'local SDK changes are stashed first.',
      confirmLabel: 'Switch',
      destructive: false,
    );
    if (!ok || !context.mounted) return;

    final outcome = await showVersionSwitchDialog(
      context,
      version: version,
      channel: channel,
      start: () => cubit.switchVersion(version, channel: channel),
    );
    if (outcome == null) {
      // Failed or closed early: the SDK may have moved, so re-read it.
      cubit.load();
      return;
    }
    cubit.load();
    if (!context.mounted) return;

    if (outcome.stashed) {
      await _notify(
        context,
        title: 'Local SDK changes were stashed',
        message:
            'They are kept as "$kSwitchStashMessage". Run "git stash pop" in '
            '${cubit.state.info?.sdkPath ?? 'the SDK folder'} to get them back.',
        severity: InfoBarSeverity.info,
      );
    }
    if (!outcome.upstreamSet && context.mounted) {
      await _notify(
        context,
        title: 'No upstream set for "$channel"',
        message:
            'origin/$channel is missing from this checkout, so "flutter '
            'upgrade" will not know where to go next.',
        severity: InfoBarSeverity.warning,
      );
    }
    if (outcome.remoteMismatch && context.mounted) {
      await _showRemoteMismatch(context, outcome);
    }
  }

  /// The SDK is cloned from a fork/mirror: the channel is right now, but
  /// Flutter still warns about the upstream. Offer the two ways out rather than
  /// rewriting someone's remote for them.
  Future<void> _showRemoteMismatch(
    BuildContext context,
    VersionSwitchOutcome outcome,
  ) async {
    final cubit = context.read<FlutterSdkCubit>();
    await displayInfoBar(
      context,
      duration: const Duration(minutes: 5),
      builder: (context, close) {
        return InfoBar(
          title: const Text('Upstream is not the official repository'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The SDK is on Flutter ${outcome.version} '
                '(${outcome.channel}), but its origin is '
                '"${outcome.remoteUrl ?? 'unknown'}". Flutter Doctor keeps '
                'warning about a non-standard remote until this is settled.',
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () {
                      close();
                      cubit.fixRemote();
                    },
                    child: const Text('Set origin to official repo'),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () {
                      close();
                      _explainMirror(context, outcome.remoteUrl);
                    },
                    child: const Text('Keep mirror'),
                  ),
                ],
              ),
            ],
          ),
          severity: InfoBarSeverity.warning,
          isLong: true,
          onClose: close,
        );
      },
    );
  }

  /// What a mirror user has to do themselves: Flutter only accepts a
  /// non-official remote when `FLUTTER_GIT_URL` names it.
  // TODO: decide where FLUTTER_GIT_URL should live — this process only, the
  // app's own settings, or the user environment via setx on Windows. Until then
  // the app only tells the user, it does not set anything.
  Future<void> _explainMirror(BuildContext context, String? remoteUrl) async {
    final url = remoteUrl ?? '<your mirror URL>';
    await showConfirmDialog(
      context,
      title: 'Keeping the mirror',
      message:
          'The remote is left as it is. Flutter expects FLUTTER_GIT_URL to '
          'name the mirror, otherwise it warns on every command:\n\n'
          'setx FLUTTER_GIT_URL "$url"\n\n'
          'Open a new terminal afterwards for it to take effect.',
      confirmLabel: 'Got it',
      destructive: false,
    );
  }

  static Future<void> _notify(
    BuildContext context, {
    required String title,
    required String message,
    required InfoBarSeverity severity,
  }) {
    return displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(title),
        content: Text(message),
        severity: severity,
        isLong: true,
        onClose: close,
      ),
    );
  }
}

class _VersionTile extends StatefulWidget {
  const _VersionTile({
    super.key,
    required this.release,
    required this.isCurrent,
    required this.onSwitch,
    required this.loadChangelog,
    required this.onOpenGitHub,
  });

  final FlutterRelease release;
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
  List<String>? _lines;

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
    return GroupedListRow(
      statusColor: widget.isCurrent ? palette.statusOk : null,
      showStatusSlot: true,
      onTap: _toggle,
      titleWidget: Row(
        children: [
          Text(
            widget.release.displayVersion,
            style: widget.isCurrent
                ? AppTextStyles.of(context).monoRowActive
                : AppTextStyles.of(context).monoRow,
          ),
          if (widget.isCurrent) ...[
            const SizedBox(width: 8),
            Text('current', style: AppTextStyles.of(context).inlineNote),
          ],
          if (widget.release.displayDartVersion != null) ...[
            const SizedBox(width: 8),
            Text(
              '· Dart ${widget.release.displayDartVersion}',
              style: AppTextStyles.of(context).rowSecondary,
            ),
          ],
        ],
      ),
      hoverActions: [
        OutlinedActionButton(
          icon: FluentIcons.globe,
          dense: true,
          tooltip: 'Open release notes on GitHub',
          onPressed: widget.onOpenGitHub,
        ),
        if (!widget.isCurrent)
          OutlinedActionButton(
            icon: FluentIcons.switch_widget,
            label: 'Switch',
            dense: true,
            onPressed: widget.onSwitch,
          ),
      ],
      trailing: [
        if (widget.release.releaseDate != null)
          Text(
            _formatDate(widget.release.releaseDate!),
            style: AppTextStyles.of(context).caption,
          ),
        AnimatedRotation(
          turns: _expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 160),
          child: Icon(
            FluentIcons.chevron_down,
            size: 13,
            color: palette.textMuted,
          ),
        ),
      ],
      below: AnimatedSize(
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
    );
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${_months[local.month - 1]} ${local.day}, ${local.year}';
  }

  Widget _changelog(AppPalette palette) {
    if (_loading) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: AppLoader(size: AppLoaderSize.small),
        ),
      );
    }
    final lines = _lines ?? const [];
    if (lines.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No changelog available from the local git history. Use the GitHub '
          'link for full release notes.',
          style: AppTextStyles.of(context).caption,
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
          Text(
            '${lines.length} commits since previous version',
            style: AppTextStyles.of(context).rowSecondary,
          ),
          const SizedBox(height: 4),
          for (final line in lines.take(200))
            Text(line, style: AppTextStyles.of(context).monoBody),
        ],
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
    final versions = await context
        .read<FlutterSdkCubit>()
        .listInstallableVersions(_channel);
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
                  'restore it to ${widget.restorable.first.originalPath}.',
                ),
                severity: InfoBarSeverity.warning,
                isLong: true,
                action: FilledButton(
                  onPressed: () => widget.onRestore(widget.restorable.first),
                  child: const Text('Restore'),
                ),
              ),
              const SizedBox(height: 18),
            ],
            Icon(
              FluentIcons.download,
              size: 24,
              color: AppPalette.of(context).textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              'No Flutter SDK found',
              textAlign: TextAlign.center,
              style: AppTextStyles.of(context).heroTitle,
            ),
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
                              child: AppLoader(size: AppLoaderSize.small),
                            ),
                          )
                        : ComboBox<String>(
                            isExpanded: true,
                            value: _version,
                            items: [
                              const ComboBoxItem(
                                value: _latest,
                                child: Text('Latest (channel tip)'),
                              ),
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
      message:
          'Append "${p.join(dir, 'bin')}" to your user PATH so "flutter" '
          'works everywhere. You must restart this app (and open terminals) '
          'for it to take effect.',
      confirmLabel: 'Add to PATH',
      destructive: false,
    );
    if (addPath && mounted) {
      try {
        await cubit.addToPath(dir);
        if (mounted) {
          await displayInfoBar(
            context,
            builder: (context, close) {
              return InfoBar(
                title: const Text('Added to PATH'),
                content: const Text(
                  'Restart the app to detect the new Flutter SDK.',
                ),
                severity: InfoBarSeverity.success,
                onClose: close,
              );
            },
          );
        }
      } catch (e) {
        if (mounted) {
          await displayInfoBar(
            context,
            builder: (context, close) {
              return InfoBar(
                title: const Text('Could not update PATH'),
                content: Text('$e'),
                severity: InfoBarSeverity.warning,
                onClose: close,
              );
            },
          );
        }
      }
    }
    widget.onInstalled();
  }
}
