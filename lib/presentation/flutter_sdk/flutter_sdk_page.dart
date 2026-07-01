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
import '../emulator/widgets/avd_dialogs.dart';

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
    final cubit = context.read<FlutterSdkCubit>();
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Flutter SDK'),
        commandBar: BlocBuilder<FlutterSdkCubit, FlutterSdkState>(
          builder: (context, state) => CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.up),
                label: const Text('Upgrade'),
                onPressed: state.info == null
                    ? null
                    : () => _run(context, 'Upgrading Flutter (${state.info!.channel})',
                        () => cubit.upgrade()),
              ),
              CommandBarButton(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2))
                    : const Icon(FluentIcons.refresh),
                label: const Text('Refresh'),
                onPressed: state.isLoading ? null : cubit.load,
              ),
            ],
          ),
        ),
      ),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CurrentSdkCard(
                  info: info,
                  onUninstall: info.sdkPath == null
                      ? null
                      : () => _uninstall(context, info.sdkPath!),
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
                        () => cubit.resetToStable(),
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
                Text('Channel', style: FluentTheme.of(context).typography.subtitle),
                const SizedBox(height: 4),
                Text(
                  'Switch release channel, then Upgrade to fetch its latest build.',
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                        color: FluentTheme.of(context)
                            .resources
                            .textFillColorSecondary,
                      ),
                ),
                const SizedBox(height: 12),
                _ChannelSection(
                  current: info.channel,
                  browsing: state.browsingChannel ?? info.channel,
                ),
                const SizedBox(height: 24),
                _VersionsSection(state: state),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Runs a streaming SDK command and reloads on success.
  static Future<void> _run(
    BuildContext context,
    String title,
    Future<RunningCommand> Function() start,
  ) async {
    final cubit = context.read<FlutterSdkCubit>();
    final ok = await showCommandProgressDialog(context, title: title, start: start);
    if (ok) cubit.load();
  }

  static Future<void> _uninstall(BuildContext context, String path) async {
    final cubit = context.read<FlutterSdkCubit>();
    final ok = await showConfirmDialog(
      context,
      title: 'Uninstall Flutter SDK?',
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

class _CurrentSdkCard extends StatelessWidget {
  const _CurrentSdkCard({
    required this.info,
    this.onUninstall,
    this.onAddToPath,
  });

  final FlutterSdkInfo info;
  final VoidCallback? onUninstall;
  final VoidCallback? onAddToPath;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Card(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF54C5F8).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(FluentIcons.developer_tools,
                size: 30, color: Color(0xFF54C5F8)),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Flutter ${info.version}',
                        style: theme.typography.title),
                    const SizedBox(width: 10),
                    _ChannelPill(channel: info.channel),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 20,
                  runSpacing: 4,
                  children: [
                    if (info.dartVersion != null)
                      _kv(theme, 'Dart', info.dartVersion!),
                    if (info.frameworkRevision != null)
                      _kv(theme, 'Revision', info.frameworkRevision!),
                    _kv(theme, 'Git repo', info.isGitRepo ? 'yes' : 'no'),
                  ],
                ),
                if (info.sdkPath != null) ...[
                  const SizedBox(height: 8),
                  Text(info.sdkPath!,
                      style: theme.typography.caption?.copyWith(
                        fontFamily: 'Consolas',
                        color: theme.resources.textFillColorTertiary,
                      )),
                ],
              ],
            ),
          ),
          if (onAddToPath != null || onUninstall != null) ...[
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (onAddToPath != null)
                  Tooltip(
                    message: 'Add Flutter to PATH so "flutter" works in any '
                        'terminal',
                    child: Button(
                      onPressed: onAddToPath,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.command_prompt, size: 14),
                          SizedBox(width: 6),
                          Text('Add to PATH'),
                        ],
                      ),
                    ),
                  ),
                if (onAddToPath != null && onUninstall != null)
                  const SizedBox(height: 8),
                if (onUninstall != null)
                  Tooltip(
                    message: 'Uninstall this Flutter SDK',
                    child: Button(
                      onPressed: onUninstall,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.delete,
                              size: 14, color: Color(0xFFC42B1C)),
                          SizedBox(width: 6),
                          Text('Uninstall',
                              style: TextStyle(color: Color(0xFFC42B1C))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(FluentThemeData theme, String k, String v) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k: ',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              )),
          Text(v, style: theme.typography.caption),
        ],
      );
}

class _ChannelSection extends StatelessWidget {
  const _ChannelSection({required this.current, required this.browsing});

  /// The channel the SDK is actually on right now.
  final String current;

  /// The channel currently being browsed (drives the version list).
  final String browsing;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final cubit = context.read<FlutterSdkCubit>();
    final pendingSwitch = browsing != current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final channel in kFlutterChannels)
              _ChannelChoice(
                channel: channel,
                selected: channel == browsing,
                isCurrent: channel == current,
                onTap: () => cubit.browseChannel(channel),
              ),
          ],
        ),
        if (pendingSwitch) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(FluentIcons.info, size: 14, color: theme.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Browsing "$browsing". Your SDK is still on '
                  '"$current". Switch to apply.',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => _switch(context, browsing),
                child: Text('Switch to $browsing'),
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
    final done = await showCommandProgressDialog(
      context,
      title: 'Switching to $channel',
      start: () => cubit.switchChannel(channel),
    );
    if (done) cubit.load();
  }
}

class _ChannelChoice extends StatelessWidget {
  const _ChannelChoice({
    required this.channel,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });

  final String channel;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accent : theme.resources.controlStrokeColorDefault,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? FluentIcons.radio_btn_on : FluentIcons.radio_btn_off,
              size: 16,
              color: selected ? accent : theme.resources.textFillColorSecondary,
            ),
            const SizedBox(width: 10),
            Text(channel,
                style: theme.typography.bodyStrong?.copyWith(
                  color: selected ? accent : null,
                )),
            if (isCurrent) ...[
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3DDC84).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Active',
                    style: TextStyle(fontSize: 10, color: Color(0xFF3DDC84))),
              ),
            ],
          ],
        ),
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
    final theme = FluentTheme.of(context);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Versions', style: theme.typography.subtitle),
            const SizedBox(width: 8),
            if (channel.isNotEmpty) _ChannelPill(channel: channel),
            const SizedBox(width: 10),
            if (state.versionsLoading)
              const SizedBox(
                  width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
            else
              Text('${state.versions.length} available',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorTertiary,
                  )),
            const Spacer(),
            SizedBox(
              width: 200,
              child: TextBox(
                placeholder: 'Filter versions…',
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(FluentIcons.search, size: 14),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Checks out a release tag in the SDK git repo. Commit or stash any '
          'local SDK changes first.',
          style: theme.typography.caption?.copyWith(
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        const SizedBox(height: 12),
        if (versions.isEmpty && !state.versionsLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _query.isNotEmpty
                  ? 'No versions match "$_query".'
                  : 'No version tags found for the "$channel" channel. '
                      'Run "git fetch --tags" in the SDK folder to pull them.',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorTertiary,
              ),
            ),
          ),
        // Bounded height so the outer scroll view stays usable.
        ...versions.take(80).map((v) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _VersionTile(
                version: v,
                isCurrent: v == current,
                onSwitch: () => _switch(context, v),
                loadChangelog: () => context
                    .read<FlutterSdkCubit>()
                    .changelog(v, _previousOf(v, state.versions)),
                onOpenGitHub: () =>
                    context.read<FlutterSdkCubit>().openReleasePage(v),
              ),
            )),
        if (versions.length > 80)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Showing first 80 of ${versions.length}. Filter to '
                'narrow down.',
                style: theme.typography.caption?.copyWith(
                  color: theme.resources.textFillColorTertiary,
                )),
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
    final done = await showCommandProgressDialog(
      context,
      title: 'Switching to Flutter $version',
      start: () => cubit.switchVersion(version),
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
    final theme = FluentTheme.of(context);
    return Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Row(
              children: [
                Icon(
                  widget.isCurrent
                      ? FluentIcons.completed_solid
                      : FluentIcons.product,
                  size: 16,
                  color: widget.isCurrent
                      ? const Color(0xFF3DDC84)
                      : theme.resources.textFillColorSecondary,
                ),
                const SizedBox(width: 12),
                Text(widget.version, style: theme.typography.bodyStrong),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Open release notes on GitHub',
                  child: IconButton(
                    icon: const Icon(FluentIcons.globe, size: 13),
                    onPressed: widget.onOpenGitHub,
                  ),
                ),
                const Spacer(),
                if (widget.isCurrent)
                  Text('Current',
                      style: theme.typography.caption
                          ?.copyWith(color: const Color(0xFF3DDC84)))
                else
                  Button(
                      onPressed: widget.onSwitch, child: const Text('Switch')),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(FluentIcons.chevron_down,
                      size: 10,
                      color: theme.resources.textFillColorSecondary),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10, left: 28),
                    child: _changelog(theme),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _changelog(FluentThemeData theme) {
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
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No changelog available from the local git history. Use the GitHub '
          'link for full release notes.',
          style: theme.typography.caption?.copyWith(
            color: theme.resources.textFillColorTertiary,
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF54C5F8), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${lines.length} commits since previous version',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              )),
          const SizedBox(height: 6),
          for (final line in lines.take(200))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text('• $line',
                  style: theme.typography.caption?.copyWith(
                    fontFamily: 'Consolas',
                    color: theme.resources.textFillColorSecondary,
                  )),
            ),
        ],
      ),
    );
  }
}

class _ChannelPill extends StatelessWidget {
  const _ChannelPill({required this.channel});

  final String channel;

  @override
  Widget build(BuildContext context) {
    final color = switch (channel) {
      'stable' => const Color(0xFF3DDC84),
      'beta' => const Color(0xFF54C5F8),
      'master' => const Color(0xFFFFB900),
      _ => const Color(0xFF767676),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(channel,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
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
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF54C5F8).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(FluentIcons.download,
                  size: 36, color: Color(0xFF54C5F8)),
            ),
            const SizedBox(height: 18),
            Text('No Flutter SDK found',
                textAlign: TextAlign.center, style: theme.typography.subtitle),
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
                size: 40, color: Color(0xFFE81123)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
