import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_result.dart';
import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/flutter_sdk_info.dart';
import '../../domain/entities/jdk.dart';
import '../../domain/entities/windows_toolchain.dart';
import '../../domain/entities/version_switch.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../../core/platform/env_persistence.dart';
import '../../core/platform/platform_service.dart';
import '../../core/platform/system_actions.dart';
import '../sdk/flutter_locator.dart';
import '../system/external_link_service.dart';
import '../trash/trash_service.dart';

/// A step of the version switch failed. Internal to [FlutterRepositoryImpl];
/// it is converted into a [VersionSwitchFailed] event once the SDK has been
/// rolled back, so callers of the stream never see an exception.
class _SwitchAbort implements Exception {
  _SwitchAbort(this.message, {this.output, this.suggestion});

  final String message;
  final String? output;
  final String? suggestion;
}

/// [FlutterRepository] backed by the `flutter` command-line tool.
@LazySingleton(as: FlutterRepository)
class FlutterRepositoryImpl implements FlutterRepository {
  FlutterRepositoryImpl(
    this._runner,
    this._locator,
    this._trash,
    this._platform,
    this._actions,
    this._links,
  );

  final CommandRunner _runner;
  final FlutterLocator _locator;
  final TrashService _trash;
  final PlatformService _platform;
  final SystemActions _actions;
  final ExternalLinkService _links;

  String get _flutter => _locator.executable;

  @override
  Future<List<Device>> listDevices() async {
    final result = await _runner.run(
      _platform.flutterExecutable,
      ['devices', '--machine'],
      timeout: const Duration(minutes: 2),
    );
    return parseFlutterDevices(result.stdout);
  }

  /// Parses `flutter devices --machine` JSON into [Device]s. Static & pure.
  static List<Device> parseFlutterDevices(String output) {
    // Flutter may print warnings before the JSON; isolate the array.
    final start = output.indexOf('[');
    final end = output.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    final dynamic decoded;
    try {
      decoded = jsonDecode(output.substring(start, end + 1));
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];

    return decoded.whereType<Map<String, dynamic>>().map((json) {
      final target = json['targetPlatform'] as String?;
      final id = json['id'] as String? ?? '';
      final isAndroid = target?.startsWith('android') ?? false;
      return Device(
        serial: id,
        state: DeviceState.device,
        model: json['name'] as String?,
        sdkInt: null,
        platform: target,
        supportsAdb: isAndroid,
      );
    }).where((d) => d.serial.isNotEmpty).toList();
  }

  // ---- SDK version management ----------------------------------------------

  @override
  Future<FlutterSdkInfo> getSdkInfo() async {
    final result = await _runner.run(
      _flutter,
      ['--version', '--machine'],
      timeout: const Duration(minutes: 2),
    );
    // A non-zero exit means flutter is missing or its SDK is broken (e.g. a
    // half-deleted folder that lost its .git). Either way it isn't usable, so
    // treat it as "not installed" and let the UI offer a fresh install.
    if (!result.isSuccess) {
      throw const ExecutableNotFoundFailure(
        'flutter',
        suggestion: 'Install a Flutter SDK, or add its "bin" folder to PATH.',
      );
    }
    var info = parseSdkInfo(result.stdout);
    // Attach the git origin URL so the UI can offer to fix a non-standard one.
    final root = info.sdkPath;
    if (info.isGitRepo && root != null) {
      try {
        final remote = await _runner.run(
          'git',
          ['-C', root, 'remote', 'get-url', 'origin'],
          timeout: const Duration(seconds: 10),
        );
        if (remote.isSuccess) {
          info = info.copyWith(remoteUrl: remote.stdout.trim());
        }
      } catch (_) {}
    }
    return info;
  }

  @override
  Future<void> fixUpstreamRemote() async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) {
      throw const UnknownFailure('This SDK is not a git checkout.');
    }
    final result = await _runner.run(
      'git',
      ['-C', root, 'remote', 'set-url', 'origin', kFlutterRepoUrl],
      timeout: const Duration(seconds: 15),
    );
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Failed to update the git remote.',
        exitCode: result.exitCode,
        output: result.combinedOutput,
      );
    }
  }

  /// Parses `flutter --version --machine` JSON. Static & pure for tests.
  static FlutterSdkInfo parseSdkInfo(String output) {
    final start = output.indexOf('{');
    final end = output.lastIndexOf('}');
    Map<String, dynamic> json = const {};
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(output.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        json = const {};
      }
    }
    final root = json['flutterRoot'] as String?;
    final isGit = root != null && Directory(p.join(root, '.git')).existsSync();
    return FlutterSdkInfo(
      version: json['frameworkVersion'] as String? ?? 'unknown',
      channel: json['channel'] as String? ?? 'unknown',
      dartVersion: json['dartSdkVersion'] as String?,
      frameworkRevision: (json['frameworkRevisionShort'] ??
          json['frameworkRevision']) as String?,
      engineRevision: (json['engineRevisionShort'] ?? json['engineRevision'])
          as String?,
      sdkPath: root,
      isGitRepo: isGit,
    );
  }

  @override
  Future<List<String>> listVersions(String channel) async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) return const [];

    // Restrict tags to those reachable from the channel's branch so each
    // channel shows its own versions.
    final ref = await _channelRef(root, channel);
    final result = await _runner.run(
      'git',
      [
        '-C', root, 'tag', '-l', '--sort=-v:refname',
        if (ref != null) ...['--merged', ref],
      ],
      timeout: const Duration(seconds: 30),
    );
    if (!result.isSuccess) return const [];
    // Stable exposes clean x.y.z releases; beta/master include pre-release tags.
    return parseVersionTags(result.stdout,
        includePreRelease: channel != 'stable');
  }

  @override
  Future<String?> sdkHeadHash() async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) return null;
    try {
      final result = await _runner.run(
        'git',
        ['-C', root, 'rev-parse', 'HEAD'],
        timeout: const Duration(seconds: 15),
      );
      final hash = result.stdout.trim();
      return result.isSuccess && hash.isNotEmpty ? hash : null;
    } catch (_) {
      return null;
    }
  }

  /// Resolves a usable git ref for [channel] (remote first, then local).
  Future<String?> _channelRef(String root, String channel) async {
    for (final ref in ['origin/$channel', channel]) {
      final r = await _runner.run(
        'git',
        ['-C', root, 'rev-parse', '--verify', '--quiet', ref],
        timeout: const Duration(seconds: 10),
      );
      if (r.isSuccess && r.stdout.trim().isNotEmpty) return ref;
    }
    return null;
  }

  /// Keeps release tags, newest first. Stable-style "3.24.1" always; when
  /// [includePreRelease] also beta/dev tags like "3.45.0-1.2.pre".
  static List<String> parseVersionTags(String output,
      {bool includePreRelease = false}) {
    final stable = RegExp(r'^\d+\.\d+\.\d+$');
    final pre = RegExp(r'^\d+\.\d+\.\d+-\d+\.\d+\.pre$');
    return const LineSplitter()
        .convert(output)
        .map((l) => l.trim())
        .where((t) =>
            stable.hasMatch(t) || (includePreRelease && pre.hasMatch(t)))
        .toList();
  }

  // ---- The SDK write lock ---------------------------------------------------
  //
  // Version switch, channel switch, upgrade and the stable reset all move HEAD
  // in the same working tree, so only one of them may be in flight at a time.
  // TODO: confirm this belongs here — the app has no operation lock of its own
  // (device/AVD cubits only track per-item busy flags), so this is deliberately
  // the single one rather than a second scheme layered on an existing lock.

  /// What currently holds the lock, e.g. "An upgrade". Null when free.
  String? _sdkOperation;

  /// Takes the lock for [operation], or throws when someone else holds it.
  void _claimSdk(String operation) {
    if (_sdkOperation != null) {
      throw UnknownFailure('$_sdkOperation is still running on this SDK.');
    }
    _sdkOperation = operation;
  }

  void _releaseSdk() => _sdkOperation = null;

  /// Holds the lock until [command] exits — a streaming command owns the SDK
  /// for as long as its process runs, not just until it is handed back.
  RunningCommand _holdUntilDone(RunningCommand command) {
    // The result is awaited by the caller too; swallowing the error here only
    // stops this second listener from reporting it as unhandled.
    command.result.then<void>((_) {}, onError: (Object _) {})
        .whenComplete(_releaseSdk);
    return command;
  }

  /// Runs [start] under the lock, releasing it again if it never gets as far as
  /// spawning the process.
  Future<RunningCommand> _locked(
    String operation,
    Future<RunningCommand> Function() start,
  ) async {
    _claimSdk(operation);
    try {
      return _holdUntilDone(await start());
    } catch (_) {
      _releaseSdk();
      rethrow;
    }
  }

  @override
  Future<RunningCommand> switchChannel(String channel,
      {bool stashLocalChanges = false}) {
    return _locked('A channel switch', () async {
      if (stashLocalChanges) await _stashCurrentSdk();
      return _runner.start(_flutter, ['channel', channel]);
    });
  }

  @override
  Future<List<String>> localChanges() async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) return const [];
    final result = await _runner.run(
      'git',
      ['-C', root, 'status', '--porcelain'],
      timeout: const Duration(seconds: 60),
    );
    if (!result.isSuccess) return const [];
    return const LineSplitter()
        .convert(result.stdout)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Moves every uncommitted change in the SDK checkout into a git stash so
  /// `flutter upgrade` (which refuses to run on a dirty tree) can proceed. The
  /// changes stay recoverable via `git stash pop`.
  Future<void> _stashLocalChanges(String root) async {
    final result = await _runner.run(
      'git',
      [
        '-C', root, 'stash', 'push', '--include-untracked',
        '-m', 'flutter-sdk-manager: local changes before upgrade',
      ],
      timeout: const Duration(minutes: 2),
    );
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Failed to stash local changes in the Flutter SDK.',
        exitCode: result.exitCode,
        output: result.combinedOutput,
        suggestion: 'Clean the SDK checkout manually with "git -C $root '
            'checkout -- .", then upgrade again.',
      );
    }
  }

  /// Stashes the active SDK's local changes, resolving its root first. No-op
  /// when the SDK is not a git checkout.
  Future<void> _stashCurrentSdk() async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root != null && info.isGitRepo) await _stashLocalChanges(root);
  }

  @override
  Future<RunningCommand> upgrade({bool stashLocalChanges = false}) {
    return _locked('An upgrade', () async {
      if (stashLocalChanges) await _stashCurrentSdk();
      return _runner.start(_flutter, ['upgrade']);
    });
  }

  @override
  Future<RunningCommand> resetToStable({bool stashLocalChanges = false}) {
    return _locked('A reset to stable', () => _resetToStable(stashLocalChanges));
  }

  Future<RunningCommand> _resetToStable(bool stashLocalChanges) async {
    final info = await getSdkInfo();
    final root = info.sdkPath;

    if (root != null && info.isGitRepo) {
      // A dirty tree blocks both the checkout below and the closing upgrade.
      if (stashLocalChanges) await _stashLocalChanges(root);
      // Do it via git so it works even from a detached/"unknown" state that the
      // `flutter channel` command refuses to fix:
      //  1) point origin at the official repo,
      //  2) put HEAD on a real `stable` branch tracking origin/stable.
      await _tryGit(root, ['remote', 'set-url', 'origin', kFlutterRepoUrl]);
      final checkout =
          await _checkoutChannelBranch(root, 'stable', 'origin/stable');
      if (!checkout) {
        // Fall back to the flutter tool if origin/stable isn't available.
        await _runner.run(_flutter, ['channel', 'stable'],
            timeout: const Duration(minutes: 2));
      }
    } else {
      await _runner.run(_flutter, ['channel', 'stable'],
          timeout: const Duration(minutes: 2));
    }
    // Stream the upgrade that re-syncs the SDK to the latest stable.
    return _runner.start(_flutter, ['upgrade']);
  }

  /// Deletes the cached version stamp so `flutter` re-reads the channel/version
  /// from git after a branch/tag change (otherwise it reports the stale one).
  void _invalidateVersionStamp(String root) {
    try {
      final stamp = File(p.join(root, 'bin', 'cache', 'flutter.version.json'));
      if (stamp.existsSync()) stamp.deleteSync();
    } catch (_) {}
  }

  /// Puts HEAD on a real [channel] branch at [ref] and points that branch at
  /// `origin/<channel>` — the shape Flutter needs to report a channel instead
  /// of "[user-branch]". Best-effort; returns whether the checkout landed.
  ///
  /// Shared by the stable reset and (in strict, step-reporting form) by the
  /// version switch below.
  Future<bool> _checkoutChannelBranch(
      String root, String channel, String ref) async {
    if (!await _tryGit(root, ['checkout', '-B', channel, ref])) return false;
    await _tryGit(root, ['branch', '--set-upstream-to=origin/$channel', channel]);
    _invalidateVersionStamp(root);
    return true;
  }

  /// Runs a git command in [root], returning whether it succeeded (best-effort).
  Future<bool> _tryGit(String root, List<String> args) async {
    try {
      final r = await _runner.run('git', ['-C', root, ...args],
          timeout: const Duration(minutes: 2));
      return r.isSuccess;
    } catch (_) {
      return false;
    }
  }

  // ---- Version switching ----------------------------------------------------

  @override
  Future<bool> isOnVersion(String version, String channel) async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) return false;
    final tag = await _git(root, ['rev-list', '-n', '1', 'refs/tags/$version'],
        timeout: const Duration(seconds: 15));
    final tagCommit = tag.isSuccess ? tag.stdout.trim() : '';
    if (tagCommit.isEmpty) return false;
    final head = await _git(root, ['rev-parse', 'HEAD'],
        timeout: const Duration(seconds: 15));
    final branch = await _git(root, ['rev-parse', '--abbrev-ref', 'HEAD'],
        timeout: const Duration(seconds: 15));
    return head.stdout.trim() == tagCommit && branch.stdout.trim() == channel;
  }

  @override
  Stream<VersionSwitchEvent> switchVersion(String version,
      {required String channel}) async* {
    if (_sdkOperation != null) {
      yield VersionSwitchFailed(
        '$_sdkOperation is still running on this SDK.',
        suggestion: 'Wait for it to finish, then switch again.',
      );
      return;
    }
    _claimSdk('A version switch');
    try {
      yield* _switchVersion(version, channel);
    } finally {
      _releaseSdk();
    }
  }

  /// The switch itself. Aborts are thrown as [_SwitchAbort] from the helpers
  /// and turned into a [VersionSwitchFailed] (after a rollback) at the bottom.
  Stream<VersionSwitchEvent> _switchVersion(
      String version, String channel) async* {
    if (!isOfficialFlutterChannel(channel) || channel == 'master') {
      yield VersionSwitchFailed(
        'Flutter $version has no channel branch to switch to.',
        suggestion: 'Pick a release from the stable or beta list.',
      );
      return;
    }
    final FlutterSdkInfo info;
    try {
      info = await getSdkInfo();
    } on Failure catch (e) {
      yield VersionSwitchFailed(e.message, suggestion: e.suggestion);
      return;
    }
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) {
      yield const VersionSwitchFailed(
        'This Flutter SDK is not a git checkout, so versions cannot be '
        'switched.',
        suggestion: 'Reinstall Flutter via git, or use channels.',
      );
      return;
    }

    // Where to return to if anything after the checkout goes wrong. A detached
    // HEAD reports the branch as "HEAD", in which case only the commit is used.
    final startBranch =
        (await _git(root, ['rev-parse', '--abbrev-ref', 'HEAD'])).stdout.trim();
    final startCommit =
        (await _git(root, ['rev-parse', 'HEAD'])).stdout.trim();

    var stashed = false;
    var checkedOut = false;

    try {
      // 1. Fetch, so the tag and origin/<channel> are both present locally.
      yield const VersionSwitchStepStarted(VersionSwitchStep.fetchingTags);
      final shallow = (await _git(root, ['rev-parse', '--is-shallow-repository']))
              .stdout
              .trim() ==
          'true';
      if (shallow) {
        yield const VersionSwitchLogged(
          'This SDK is a shallow clone, so its full history has to be fetched '
          'before a release tag can be checked out. This takes a few minutes.',
        );
        yield* _stream('git', ['-C', root, 'fetch', '--unshallow', '--tags'],
            onFail: 'Failed to fetch the full history of the SDK checkout.');
      } else {
        yield* _stream('git', ['-C', root, 'fetch', 'origin', '--tags', '--prune'],
            onFail: 'Failed to fetch tags from origin.');
      }

      // 2. The tag has to exist locally or the checkout below fails cryptically.
      // No `^{commit}` peel here: commands run through cmd.exe on Windows,
      // which swallows the caret and would turn this into a false negative.
      final tag =
          await _git(root, ['rev-parse', '--verify', '--quiet', 'refs/tags/$version']);
      if (tag.stdout.trim().isEmpty) {
        throw _SwitchAbort(
          'Release tag $version not found — the SDK repo may be a partial '
          'mirror.',
          suggestion: 'Check the "origin" remote of $root, or reinstall the '
              'SDK from the official repository.',
        );
      }

      // 3. A fork/mirror stays a fork/mirror: rewriting the remote behind the
      // user's back is not ours to do, so it is only reported.
      final remote = await _git(root, ['remote', 'get-url', 'origin'],
          timeout: const Duration(seconds: 15));
      final remoteUrl = remote.isSuccess && remote.stdout.trim().isNotEmpty
          ? remote.stdout.trim()
          : null;
      if (!isOfficialFlutterRemote(remoteUrl)) {
        yield VersionSwitchLogged(
          'origin is "${remoteUrl ?? 'unknown'}", not the official Flutter '
          'repository. Leaving it as it is.',
        );
      }

      // 4. git refuses to move HEAD over uncommitted work; park it.
      final status = await _git(root, ['status', '--porcelain'],
          timeout: const Duration(minutes: 1));
      if (status.stdout.trim().isNotEmpty) {
        yield const VersionSwitchLogged(
          'Local SDK changes found — stashing them as "$kSwitchStashMessage".',
        );
        final stash = await _git(root, [
          'stash', 'push', '--include-untracked', '-m', kSwitchStashMessage,
        ]);
        if (!stash.isSuccess) {
          throw _SwitchAbort(
            'Failed to stash the local changes in the SDK, so nothing was '
            'switched.',
            output: stash.combinedOutput,
            suggestion: 'Commit or discard the changes in $root, then switch '
                'again.',
          );
        }
        stashed = true;
      }

      // 5. The tag onto its channel branch — this is what keeps the channel
      // name (and therefore flutter doctor) correct.
      yield const VersionSwitchStepStarted(VersionSwitchStep.checkingOut);
      yield* _stream(
        'git',
        ['-C', root, 'checkout', '-B', channel, 'refs/tags/$version'],
        onFail: 'Failed to check out Flutter $version on the "$channel" branch.',
      );
      checkedOut = true;
      _invalidateVersionStamp(root);

      // 6. Upstream, so `flutter upgrade` knows where to go next.
      yield const VersionSwitchStepStarted(VersionSwitchStep.settingUpstream);
      var upstreamSet = false;
      final hasRemoteBranch = await _ensureChannelTracking(root, channel);
      if (hasRemoteBranch) {
        final upstream = await _git(
            root, ['branch', '--set-upstream-to=origin/$channel', channel]);
        if (!upstream.isSuccess) {
          throw _SwitchAbort(
            'Failed to point "$channel" at origin/$channel.',
            output: upstream.combinedOutput,
          );
        }
        upstreamSet = true;
        yield VersionSwitchLogged(upstream.combinedOutput.trim());
      } else {
        yield VersionSwitchLogged(
          'origin/$channel is not in this checkout, so no upstream was set. '
          '"flutter upgrade" will not work until it is fetched.',
          isError: true,
        );
      }

      // 7. Any flutter command rebuilds the snapshot for the new version.
      //
      // Deliberately not fatal: by now the checkout and the upstream are both
      // correct, so the SDK is a valid $channel install whatever happens here.
      // A snapshot the antivirus held open is rebuilt by the next flutter
      // command anyway — rolling the whole switch back over it would be worse.
      yield const VersionSwitchStepStarted(VersionSwitchStep.rebuildingCache);
      var toolCacheRebuilt = false;
      try {
        final rebuild = await _runner.start(_flutterIn(root), ['--version']);
        await for (final line in rebuild.output) {
          yield VersionSwitchLogged(line.text, isError: line.isError);
        }
        toolCacheRebuilt = (await rebuild.result).isSuccess;
      } on Failure catch (e) {
        yield VersionSwitchLogged(e.message, isError: true);
      }
      if (!toolCacheRebuilt) {
        yield VersionSwitchLogged(
          'Flutter could not rebuild its tool cache for $version. The SDK is '
          'on $version ($channel) regardless; the next flutter command will '
          'rebuild it.',
          isError: true,
        );
      }

      yield const VersionSwitchStepStarted(VersionSwitchStep.done);
      yield VersionSwitchSucceeded(VersionSwitchOutcome(
        version: version,
        channel: channel,
        stashed: stashed,
        remoteUrl: remoteUrl,
        upstreamSet: upstreamSet,
        toolCacheRebuilt: toolCacheRebuilt,
      ));
    } on _SwitchAbort catch (abort) {
      final restore = checkedOut
          ? 'git -C "$root" checkout -B '
              '${startBranch.isEmpty || startBranch == 'HEAD' ? channel : startBranch} '
              '$startCommit'
          : null;
      var rolledBack = false;
      if (checkedOut) {
        yield VersionSwitchLogged(
          'Rolling the SDK back to ${startCommit.isEmpty ? 'its previous '
              'commit' : startCommit}…',
          isError: true,
        );
        rolledBack = await _rollback(root, startBranch, startCommit);
      }
      yield VersionSwitchFailed(
        abort.output == null || abort.output!.isEmpty
            ? abort.message
            : '${abort.message}\n${abort.output}',
        suggestion: abort.suggestion ??
            (checkedOut && !rolledBack && restore != null
                ? 'The SDK is left on $version. Run "$restore" to put it back.'
                : null),
        rolledBack: rolledBack,
        stashed: stashed,
      );
    }
  }

  /// Makes `origin/<channel>` exist as a remote-tracking branch, so the channel
  /// branch can be pointed at it. Returns whether it is there afterwards.
  ///
  /// `git clone -b stable` — the recipe on Flutter's own install page — writes
  /// a single-branch refspec, so `origin/beta` never appears and
  /// `--set-upstream-to` fails with "not a branch" even after `--unshallow
  /// --tags`. Widening the refspec and fetching that one branch repairs it; the
  /// config line is only added when nothing maps the branch already, so
  /// switching repeatedly does not pile up duplicates.
  Future<bool> _ensureChannelTracking(String root, String channel) async {
    if (await _hasRemoteBranch(root, channel)) return true;

    final refspecs =
        await _git(root, ['config', '--get-all', 'remote.origin.fetch']);
    final mapped = const LineSplitter().convert(refspecs.stdout).any((line) =>
        line.contains('refs/heads/*') ||
        line.contains('refs/heads/$channel:'));
    if (!mapped) {
      await _tryGit(root, [
        'config', '--add', 'remote.origin.fetch',
        '+refs/heads/$channel:refs/remotes/origin/$channel',
      ]);
    }
    await _tryGit(root, [
      'fetch', 'origin', '+refs/heads/$channel:refs/remotes/origin/$channel',
    ]);
    return _hasRemoteBranch(root, channel);
  }

  Future<bool> _hasRemoteBranch(String root, String channel) async =>
      (await _git(root,
              ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/$channel']))
          .stdout
          .trim()
          .isNotEmpty;

  /// Runs a git command in [root] and buffers its output.
  Future<CommandResult> _git(
    String root,
    List<String> args, {
    Duration timeout = const Duration(minutes: 2),
  }) =>
      _runner.run('git', ['-C', root, ...args], timeout: timeout);

  /// Runs [executable], forwarding its output as log events. Throws
  /// [_SwitchAbort] carrying [onFail] when it cannot start or exits non-zero.
  ///
  /// Deliberately untimed: an unshallow fetch of the Flutter repo runs for
  /// minutes on a slow connection and killing it mid-way is worse than waiting.
  Stream<VersionSwitchEvent> _stream(
    String executable,
    List<String> arguments, {
    required String onFail,
  }) async* {
    final RunningCommand command;
    try {
      command = await _runner.start(executable, arguments);
    } on Failure catch (e) {
      throw _SwitchAbort(onFail, output: e.message, suggestion: e.suggestion);
    }
    await for (final line in command.output) {
      yield VersionSwitchLogged(line.text, isError: line.isError);
    }
    final result = await command.result;
    if (!result.isSuccess) {
      throw _SwitchAbort(onFail, output: result.combinedOutput);
    }
  }

  /// Puts HEAD back where the switch found it. Best-effort: the caller reports
  /// the manual command when this returns false.
  Future<bool> _rollback(String root, String branch, String commit) async {
    if (commit.isEmpty) return false;
    final ok = branch.isEmpty || branch == 'HEAD'
        ? await _tryGit(root, ['checkout', '--force', commit])
        : await _tryGit(root, ['checkout', '-B', branch, commit]);
    if (ok) _invalidateVersionStamp(root);
    return ok;
  }

  /// The `flutter` of the SDK being switched, not whatever is on PATH — they
  /// are the same install in practice, but the switch must rebuild *this* one.
  String _flutterIn(String root) {
    final exe =
        p.join(root, 'bin', _platform.flutterExecutable);
    return File(exe).existsSync() ? exe : _flutter;
  }

  @override
  Future<List<String>> changelog(
      String version, String? previousVersion) async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) return const [];

    final hasPrev = previousVersion != null && previousVersion.isNotEmpty;
    final args = [
      '-C', root, 'log',
      '--no-merges',
      '--pretty=format:%s',
      '-n', hasPrev ? '400' : '50',
      if (hasPrev) '$previousVersion..$version' else version,
    ];
    final result = await _runner.run('git', args,
        timeout: const Duration(seconds: 30));
    if (!result.isSuccess) return const [];
    return const LineSplitter()
        .convert(result.stdout)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Future<RunningCommand> installSdk(String directory, String ref) async {
    final dir = directory.trim();
    if (dir.isEmpty) {
      throw const UnknownFailure('Choose an install folder first.');
    }
    final target = Directory(dir);
    if (target.existsSync() && target.listSync().isNotEmpty) {
      // Never auto-delete a non-empty folder — it could be a working SDK. If it
      // already holds a Flutter, say so; otherwise ask for an empty folder.
      final isFlutter =
          File(p.join(dir, 'bin', _platform.flutterExecutable)).existsSync() ||
          Directory(p.join(dir, 'packages')).existsSync();
      throw FileSystemFailure(
        isFlutter
            ? 'A Flutter SDK already exists at "$dir". Press Refresh to use it, '
                'or uninstall it first.'
            : 'Folder "$dir" is not empty. Pick an empty/new folder, or clear '
                'it first.',
      );
    }
    // `-b` accepts a channel branch (stable/beta/master) or a version tag.
    return _runner.start('git', ['clone', '-b', ref, kFlutterRepoUrl, dir]);
  }

  @override
  Future<List<String>> listInstallableVersions(String channel) async {
    try {
      final response = await Dio().get<dynamic>(
        'https://storage.googleapis.com/flutter_infra_release/releases/'
        'releases_windows.json',
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      final map = data is String
          ? jsonDecode(data) as Map<String, dynamic>
          : data as Map<String, dynamic>;
      final releases = (map['releases'] as List).cast<Map<String, dynamic>>();
      final versions = <String>[];
      final seen = <String>{};
      for (final r in releases) {
        if (r['channel'] != channel) continue;
        final v = r['version'] as String?;
        if (v == null || !seen.add(v)) continue;
        versions.add(v);
      }
      return versions;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> addSdkToPath(String sdkDir) async {
    final bin = p.join(sdkDir, 'bin');
    final result = await _actions.appendToUserPath(bin);
    if (result.success) return;
    throw ProcessFailure(
      result.note ?? 'Could not update PATH automatically.',
      exitCode: -1,
      suggestion: 'Add "$bin" to your PATH manually.',
    );
  }

  @override
  Future<bool> isSdkOnPath(String sdkDir) async {
    final bin = p.join(sdkDir, 'bin');
    final windows = _platform.operatingSystem == 'windows';
    // Two PATHs matter and neither alone is enough: the process one is what
    // this app inherited at launch (so it misses an entry added since), the
    // user one is what a new terminal will see (so it misses entries the
    // machine or the session put there). Either counts.
    final inherited = Platform.environment['PATH'] ?? '';
    if (pathListContains(inherited, bin, windows: windows)) return true;
    final user = await _actions.readUserPath();
    return pathListContains(user, bin, windows: windows);
  }

  @override
  Future<void> uninstallSdk(String sdkPath) async {
    final dir = Directory(sdkPath);
    if (!dir.existsSync()) {
      throw FileSystemFailure('Flutter SDK folder not found: $sdkPath');
    }
    // Safety: only delete something that looks like a Flutter SDK (a full one,
    // or leftovers from a previous partial uninstall).
    final looksLikeFlutter =
        File(p.join(sdkPath, 'bin', _platform.flutterExecutable))
                .existsSync() ||
        Directory(p.join(sdkPath, 'bin')).existsSync() ||
        Directory(p.join(sdkPath, 'packages')).existsSync() ||
        p.basename(sdkPath).toLowerCase() == 'flutter';
    if (!looksLikeFlutter) {
      throw FileSystemFailure(
        '"$sdkPath" does not look like a Flutter SDK — refusing to delete it.',
      );
    }

    // Soft-delete: move to the trash (kept 24h) instead of erasing, so the user
    // can restore or cancel. This is also an instant move, not a slow delete.
    await _trash.trash(sdkPath, label: 'Flutter SDK');
  }

  @override
  Future<void> openReleasePage(String version) async {
    await _links.open(
      'https://github.com/flutter/flutter/releases/tag/$version',
    );
  }

  @override
  Future<String?> configuredJdkDir() async {
    try {
      final result = await _runner.run(
        _flutter,
        ['config', '--list'],
        timeout: const Duration(minutes: 1),
      );
      if (!result.isSuccess) return null;
      return parseFlutterJdkDir(result.combinedOutput);
    } on Failure {
      // No Flutter, or it would not answer: the page still lists JDKs, it just
      // cannot say which one Flutter was told to use.
      return null;
    }
  }

  @override
  Future<void> setJdkDir(String path) async {
    final result = await _runner.run(
      _flutter,
      ['config', '--jdk-dir=$path'],
      timeout: const Duration(minutes: 2),
    );
    if (result.isSuccess) return;
    throw ProcessFailure(
      'Flutter refused to set the JDK directory.',
      exitCode: result.exitCode,
      output: result.combinedOutput.trim(),
      suggestion: 'Check that "$path" is a JDK root, not its bin folder.',
    );
  }

  @override
  Future<FlutterFlagState> windowsDesktopFlag() async {
    try {
      final result = await _runner.run(
        _flutter,
        ['config', '--list'],
        timeout: const Duration(minutes: 1),
      );
      if (!result.isSuccess) return FlutterFlagState.unknown;
      return parseFlutterConfigFlag(
        result.combinedOutput,
        'enable-windows-desktop',
      );
    } on Failure {
      return FlutterFlagState.unknown;
    }
  }

  @override
  Future<void> setWindowsDesktopEnabled(bool enabled) async {
    final flag = enabled
        ? '--enable-windows-desktop'
        : '--no-enable-windows-desktop';
    final result = await _runner.run(
      _flutter,
      ['config', flag],
      timeout: const Duration(minutes: 2),
    );
    if (result.isSuccess) return;
    throw ProcessFailure(
      'Flutter refused to change the Windows desktop setting.',
      exitCode: result.exitCode,
      output: result.combinedOutput.trim(),
    );
  }

  @override
  Future<void> openPullRequest(int number) async {
    await _links.open('https://github.com/flutter/flutter/pull/$number');
  }
}
