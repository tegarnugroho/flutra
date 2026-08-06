import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/flutter_release.dart';
import '../../domain/entities/flutter_sdk_info.dart';
import '../../domain/entities/version_switch.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../../infrastructure/flutter/flutter_releases_service.dart';
import '../../infrastructure/trash/trash_entry.dart';
import '../../infrastructure/trash/trash_service.dart';

part 'flutter_sdk_state.dart';

/// Drives the Flutter SDK screen: reads the active SDK and switches
/// channels/versions.
@injectable
class FlutterSdkCubit extends Cubit<FlutterSdkState> {
  FlutterSdkCubit(this._repository, this._trash, this._releases)
      : super(const FlutterSdkState());

  final FlutterRepository _repository;
  final TrashService _trash;
  final FlutterReleasesService _releases;

  /// Cached across channel switches so browsing doesn't re-hit the network.
  FlutterReleasesIndex? _index;

  Future<void> load({bool forceRefresh = false}) async {
    if (isClosed) return;
    emit(state.copyWith(status: FlutterSdkStatus.loading, clearError: true));
    // Recently-uninstalled SDKs that can still be restored (24h window).
    final restorable = await _restorable();
    try {
      final info = await _repository.getSdkInfo();
      if (isClosed) return;
      // Default browsing to the active channel, or stable if it's unknown.
      final channel = info.isKnownChannel ? info.channel : 'stable';
      final head = await _repository.sdkHeadHash();
      final releases = await _releasesFor(channel, forceRefresh: forceRefresh);
      if (isClosed) return;
      final index = _index;
      emit(state.copyWith(
        status: FlutterSdkStatus.ready,
        info: info,
        releases: releases,
        browsingChannel: channel,
        versionsLoading: false,
        restorable: restorable,
        headHash: head,
        installedRelease: head == null ? null : index?.byHash(head),
        latestRelease: index?.latestFor(channel),
        clearReleaseMatches: true,
        versionSource: _source,
      ));
    } on ExecutableNotFoundFailure {
      // No Flutter on PATH — offer to install (or restore a recent one).
      if (!isClosed) {
        emit(state.copyWith(
            status: FlutterSdkStatus.notInstalled, restorable: restorable));
      }
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    }
  }

  Future<RunningCommand> installSdk(String directory, String ref) =>
      _repository.installSdk(directory, ref);

  /// Versions installable from scratch (no local SDK yet), newest first.
  Future<List<String>> listInstallableVersions(String channel) async {
    try {
      final index = await _releases.getReleases();
      return index.forChannel(channel).map((r) => r.gitTag).toList();
    } catch (_) {
      return _repository.listInstallableVersions(channel);
    }
  }

  Future<void> addToPath(String sdkDir) => _repository.addSdkToPath(sdkDir);

  Future<void> uninstall() async {
    final path = state.info?.sdkPath;
    if (path == null) return;
    try {
      await _repository.uninstallSdk(path);
      await load();
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    }
  }

  /// Points the SDK's git origin at the official repo, then reloads.
  Future<void> fixRemote() async {
    try {
      await _repository.fixUpstreamRemote();
      await load();
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    }
  }

  /// Restores a soft-deleted Flutter SDK back to its original location.
  Future<void> restore(TrashEntry entry) async {
    try {
      await _trash.restore(entry);
      await load();
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    }
  }

  /// Trashed Flutter SDKs still within the 24h restore window.
  Future<List<TrashEntry>> _restorable() async {
    try {
      final all = await _trash.list();
      return all.where((e) => e.label == 'Flutter SDK').toList();
    } catch (_) {
      return const [];
    }
  }

  /// Switches the browsed channel and reloads its version list (does NOT change
  /// the active SDK channel).
  Future<void> browseChannel(String channel) async {
    if (isClosed || channel == state.browsingChannel) return;
    emit(state.copyWith(browsingChannel: channel, versionsLoading: true));
    final releases = await _releasesFor(channel);
    if (isClosed) return;
    final head = state.headHash;
    emit(state.copyWith(
      releases: releases,
      versionsLoading: false,
      // The current marker follows the commit, so it only shows on the channel
      // that actually publishes it.
      installedRelease: head == null ? null : _index?.byHash(head),
      clearReleaseMatches: true,
      latestRelease: state.latestRelease,
      versionSource: _source,
    ));
  }

  /// Where the last list came from, for the offline caption.
  VersionSource _source = VersionSource.releaseIndex;

  /// Releases for [channel] from the official index, falling back to local git
  /// tags when the index is unreachable and nothing is cached.
  Future<List<FlutterRelease>> _releasesFor(
    String channel, {
    bool forceRefresh = false,
  }) async {
    try {
      final index = await _releases.getReleases(forceRefresh: forceRefresh);
      _index = index;
      _source = _releases.servingStaleCache
          ? VersionSource.staleCache
          : VersionSource.releaseIndex;
      return index.forChannel(channel);
    } catch (_) {
      _index = null;
      _source = VersionSource.gitTags;
      try {
        final tags = await _repository.listVersions(channel);
        return tags.map((t) => FlutterRelease.fromTag(t, channel)).toList();
      } on Failure {
        return const [];
      }
    }
  }

  Future<RunningCommand> switchChannel(String channel,
          {bool stashLocalChanges = false}) =>
      _repository.switchChannel(channel,
          stashLocalChanges: stashLocalChanges);

  /// Uncommitted changes in the SDK checkout, as `git status --porcelain`
  /// lines. Non-empty means `flutter upgrade`/version switches would fail.
  Future<List<String>> localChanges() async {
    try {
      return await _repository.localChanges();
    } on Failure {
      return const [];
    }
  }

  Future<RunningCommand> upgrade({bool stashLocalChanges = false}) =>
      _repository.upgrade(stashLocalChanges: stashLocalChanges);

  Future<RunningCommand> resetToStable({bool stashLocalChanges = false}) =>
      _repository.resetToStable(stashLocalChanges: stashLocalChanges);

  /// Moves the SDK to [version] on its [channel] branch, one event per stage.
  Stream<VersionSwitchEvent> switchVersion(String version,
          {required String channel}) =>
      _repository.switchVersion(version, channel: channel);

  /// Whether switching to [version] on [channel] would change nothing.
  Future<bool> isOnVersion(String version, String channel) async {
    try {
      return await _repository.isOnVersion(version, channel);
    } on Failure {
      return false;
    }
  }

  Future<List<String>> changelog(String version, String? previousVersion) =>
      _repository.changelog(version, previousVersion);

  Future<void> openReleasePage(String version) =>
      _repository.openReleasePage(version);

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(status: FlutterSdkStatus.failure, errorMessage: message));
  }
}
