import 'dart:async';

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
import '../common/app_loader.dart';
import '../common/busy_dialog.dart';
import '../common/command_progress_dialog.dart';
import '../common/compact_field.dart';
import '../common/confirm_dialog.dart';
import '../common/empty_state.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'version_switch_dialog.dart';
import 'widgets/channel_tabs.dart';
import 'widgets/sdk_identity_panel.dart';
import 'widgets/version_tile.dart';

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

class _FlutterSdkView extends StatefulWidget {
  const _FlutterSdkView();

  @override
  State<_FlutterSdkView> createState() => _FlutterSdkViewState();
}

class _FlutterSdkViewState extends State<_FlutterSdkView> {
  /// Tiles shown before the "older versions" footer takes over. The index
  /// reaches back to v1.0.0; nobody scrolls that on purpose.
  static const _initialVersionCount = 20;

  /// Roughly one collapsed tile plus its gap. Only used to jump the list to a
  /// release that has not been built yet — an estimate is enough, because the
  /// release being jumped to is the newest one, at or near the top.
  static const _estimatedTileExtent = 62.0;

  /// How long a jumped-to tile keeps its accent outline.
  static const _highlightDuration = Duration(milliseconds: 1600);

  final _scroll = ScrollController();
  Timer? _highlightTimer;

  String _query = '';

  /// Identity of the one open tile — the accordion is a single value, so
  /// opening one closes the other by construction.
  String? _expandedId;
  String? _highlightId;

  bool _showOlder = false;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Keyed by release identity rather than index, so an open tile survives a
  /// filter keystroke and never follows the position it happened to sit at.
  static String _idOf(FlutterRelease release) =>
      '${release.channel}/${release.version}/${release.hash}';

  void _toggle(FlutterRelease release) {
    final id = _idOf(release);
    setState(() => _expandedId = _expandedId == id ? null : id);
  }

  /// Opens the newest release on the channel and brings it into view.
  void _revealLatest(List<FlutterRelease> shown, FlutterRelease latest) {
    final id = _idOf(latest);
    final index = shown.indexWhere((r) => _idOf(r) == id);
    if (index < 0) return;
    setState(() {
      _expandedId = id;
      _highlightId = id;
      // A release below the initial cut cannot be scrolled to while the footer
      // is still hiding it.
      if (index >= _initialVersionCount) _showOlder = true;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(_highlightDuration, () {
      if (mounted) setState(() => _highlightId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = (index * _estimatedTileExtent)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

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
          child: LoadingSwitcher(
            showSkeleton: state.isFirstLoad,
            skeleton: const FlutterSdkSkeleton(),
            builder: (context) => _loaded(context, state),
          ),
        );
      },
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

    final shown = _visibleReleases(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SdkIdentityPanel(
                info: info,
                updateAvailable: state.updateAvailable,
                latestVersion: state.latestRelease?.displayVersion,
                pathStatus: state.pathStatus,
                onAddToPath: info.sdkPath == null
                    ? null
                    : () => _addToPath(context, info.sdkPath!),
                onRevealLatest: () {
                  final latest = state.latestRelease;
                  if (latest != null) _revealLatest(shown, latest);
                },
              ),
              ..._warnings(context, info, cubit),
              const SizedBox(height: 18),
              _ChannelRow(
                current: info.channel,
                browsing: state.browsingChannel ?? info.channel,
                count: shown.length,
                loading: state.versionsLoading,
                onQueryChanged: (v) => setState(() {
                  _query = v;
                  _showOlder = false;
                }),
              ),
              const SizedBox(height: 8),
              Text(_caption(state), style: AppTextStyles.of(context).caption),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Only the version list scrolls; the panel and channel row stay put.
        Expanded(child: _versions(context, state, shown)),
      ],
    );
  }

  /// The blockers that are about the checkout rather than about a version.
  List<Widget> _warnings(
    BuildContext context,
    FlutterSdkInfo info,
    FlutterSdkCubit cubit,
  ) {
    return [
      if (!info.isKnownChannel) ...[
        const SizedBox(height: 12),
        InfoBar(
          title: const Text('Off the official channel'),
          content: Text(
            'The SDK is on "${info.channel}", which is not a release channel, '
            'so flutter reports an unknown channel. Switching a version here '
            'never causes this — it means the checkout was moved outside the '
            'app. Reset to stable to return to an official channel and its '
            'latest build.',
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
            'The SDK git remote is "${info.remoteUrl ?? 'unknown'}", which '
            'triggers a "not a standard remote" warning in Flutter Doctor. '
            'Point it at the official repository.',
          ),
          severity: InfoBarSeverity.warning,
          isLong: true,
          action: FilledButton(
            onPressed: cubit.fixRemote,
            child: const Text('Fix remote'),
          ),
        ),
      ],
    ];
  }

  /// Releases on the browsed channel that survive the filter.
  List<FlutterRelease> _visibleReleases(FlutterSdkState state) {
    final query = _query.trim();
    if (query.isEmpty) return state.releases;
    return state.releases
        .where((r) => r.displayVersion.contains(query))
        .toList();
  }

  Widget _versions(
    BuildContext context,
    FlutterSdkState state,
    List<FlutterRelease> shown,
  ) {
    final text = AppTextStyles.of(context);

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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          'master is a rolling branch with no versioned releases. Switch to it '
          'above, then use Upgrade to move to its tip.',
          style: text.caption,
        ),
      );
    }

    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            _query.trim().isNotEmpty
                ? 'No versions match "${_query.trim()}".'
                : state.versionsLoading
                ? 'Loading releases…'
                : 'No releases found for the "$channel" channel.',
            style: text.caption,
          ),
        ),
      );
    }

    final capped = _showOlder || shown.length <= _initialVersionCount
        ? shown.length
        : _initialVersionCount;
    final hasFooter = capped < shown.length;

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: capped + (hasFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i == capped) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _FooterLink(
              label: 'Show older versions (${shown.length - capped} more)',
              onTap: () => setState(() => _showOlder = true),
            ),
          );
        }
        final release = shown[i];
        final id = _idOf(release);
        return VersionTile(
          key: ValueKey(id),
          release: release,
          isCurrent: _isCurrent(state, release),
          expanded: _expandedId == id,
          highlighted: _highlightId == id,
          dartBadge: _dartBadge(shown, i),
          onToggle: () => _toggle(release),
          onSwitch: () => _switch(context, release),
          loadChangelog: () => context
              .read<FlutterSdkCubit>()
              .changelog(release.gitTag, _previousOf(i, shown)),
          onOpenGitHub: () =>
              context.read<FlutterSdkCubit>().openReleasePage(release.gitTag),
          onOpenPullRequest: (number) =>
              context.read<FlutterSdkCubit>().openPullRequest(number),
        );
      },
    );
  }

  /// The Dart version to call out on the tile at [index]: set only where the
  /// bundled Dart minor changes from the newer release above it.
  static String? _dartBadge(List<FlutterRelease> shown, int index) {
    if (index == 0) return null;
    final mine = dartMinor(shown[index]);
    final above = dartMinor(shown[index - 1]);
    if (mine == null || above == null || mine == above) return null;
    return shown[index].displayDartVersion;
  }

  /// The current tile is decided by commit, not version string — a re-released
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

  String _caption(FlutterSdkState state) {
    final source = switch (state.versionSource) {
      VersionSource.releaseIndex =>
        'Official Flutter releases. Switching checks the release tag out onto '
            'its channel branch, so the SDK stays on stable or beta.',
      VersionSource.staleCache =>
        'Offline — showing the cached release list. Press Refresh to retry.',
      VersionSource.gitTags =>
        'Offline — showing release tags from the local git checkout.',
    };
    if (!state.isUnlistedCommit) return source;
    return '$source Local SDK is on an unlisted commit '
        '${state.shortHeadHash} — no tile is marked current.';
  }

  /// The next-older release in the list, used as the changelog baseline.
  static String? _previousOf(int index, List<FlutterRelease> all) =>
      index + 1 < all.length ? all[index + 1].gitTag : null;

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
    if (!outcome.toolCacheRebuilt && context.mounted) {
      await _notify(
        context,
        title: 'Tool cache was not rebuilt',
        message:
            'The SDK is on ${outcome.version} (${outcome.channel}), but '
            '"flutter --version" did not finish. The first flutter command you '
            'run rebuilds the cache itself.',
        severity: InfoBarSeverity.warning,
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

/// Channel tabs on the left, how many versions they hold and a filter on the
/// right, with the "you are browsing another channel" note underneath.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.current,
    required this.browsing,
    required this.count,
    required this.loading,
    required this.onQueryChanged,
  });

  /// The channel the SDK is actually on right now.
  final String current;

  /// The channel currently being browsed (drives the version list).
  final String browsing;

  final int count;
  final bool loading;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    final cubit = context.read<FlutterSdkCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ChannelTabs(
              channels: kFlutterChannels,
              selected: browsing,
              onChanged: cubit.browseChannel,
            ),
            const SizedBox(width: 10),
            if (loading) AppLoader(size: AppLoaderSize.small),
            const Spacer(),
            Text('$count versions', style: text.caption),
            const SizedBox(width: 10),
            CompactField(
              width: 200,
              placeholder: 'Filter versions',
              onChanged: onQueryChanged,
            ),
          ],
        ),
        if (browsing != current) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(FluentIcons.info, size: 13, color: palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Browsing "$browsing". Your SDK is still on "$current". '
                  'Switch to apply.',
                  style: text.caption,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedActionButton(
                icon: FluentIcons.switch_widget,
                label: 'Switch to $browsing',
                dense: true,
                onPressed: () => _switchChannel(context, browsing),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _switchChannel(BuildContext context, String channel) async {
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

/// The list's own footer link.
class _FooterLink extends StatefulWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Text(
            widget.label,
            style: AppTextStyles.of(context).caption.copyWith(
              fontSize: 11.5,
              color: palette.accent,
              decoration: _hovered ? TextDecoration.underline : null,
              decorationColor: palette.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Page-header actions: Refresh, Upgrade (primary) and an overflow menu holding
/// the rarely-used (and destructive) commands.
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
              // Diagnostic only — kept out of the panel, not actionable here.
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
                    _FlutterSdkViewState._uninstall(
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
          icon: FluentIcons.refresh,
          label: 'Refresh',
          busy: state.isLoading,
          // Refresh always re-downloads the release index.
          onPressed: () => cubit.load(forceRefresh: true),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: state.info == null
              ? null
              : () => _FlutterSdkViewState._run(
                  context,
                  'Upgrading Flutter (${state.info!.channel})',
                  (stash) => cubit.upgrade(stashLocalChanges: stash),
                ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.up, size: 12),
              SizedBox(width: 7),
              Text('Upgrade'),
            ],
          ),
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
