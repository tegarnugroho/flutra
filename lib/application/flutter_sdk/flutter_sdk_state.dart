part of 'flutter_sdk_cubit.dart';

enum FlutterSdkStatus { initial, loading, ready, notInstalled, failure }

/// Where the browsed version list came from.
enum VersionSource {
  /// Flutter's official release index (fresh or cached within 6h).
  releaseIndex,

  /// The release index, served from a cache older than 6h because the network
  /// was unreachable.
  staleCache,

  /// Local git tags, because the index was unavailable and nothing was cached.
  gitTags,
}

/// Whether the SDK's `bin` folder is on PATH.
enum SdkPathStatus {
  /// Not looked at yet, or the check failed — the UI says nothing either way.
  unknown,
  present,
  absent,
}

/// Immutable state for the Flutter SDK screen.
class FlutterSdkState extends Equatable {
  const FlutterSdkState({
    this.status = FlutterSdkStatus.initial,
    this.info,
    this.releases = const [],
    this.browsingChannel,
    this.versionsLoading = false,
    this.restorable = const [],
    this.errorMessage,
    this.headHash,
    this.installedRelease,
    this.latestRelease,
    this.versionSource = VersionSource.releaseIndex,
    this.pathStatus = SdkPathStatus.unknown,
  });

  final FlutterSdkStatus status;
  final FlutterSdkInfo? info;

  /// Releases on [browsingChannel], newest first.
  final List<FlutterRelease> releases;

  /// The channel whose versions are currently listed (browsing only — does not
  /// change the active SDK channel).
  final String? browsingChannel;
  final bool versionsLoading;

  /// Recently soft-deleted Flutter SDKs that can still be restored (24h window).
  final List<TrashEntry> restorable;

  final String? errorMessage;

  /// The local checkout's HEAD commit, used to mark the current version.
  final String? headHash;

  /// The release [headHash] resolves to, if it is a published one.
  final FlutterRelease? installedRelease;

  /// Newest release on the *active* channel, per `current_release`.
  final FlutterRelease? latestRelease;

  final VersionSource versionSource;

  /// Whether `<sdkPath>/bin` is on PATH, re-read after adding it.
  final SdkPathStatus pathStatus;

  bool get isLoading => status == FlutterSdkStatus.loading;

  /// True until the first load settles, so a screen with no data yet shows its
  /// skeleton from the very first frame.
  ///
  /// `isLoading` alone is not enough: the cubit is created during the first
  /// build and its status is still `initial` while that frame renders, which
  /// would flash the centred empty state before the skeleton takes over.
  bool get isFirstLoad =>
      info == null &&
      (status == FlutterSdkStatus.initial ||
          status == FlutterSdkStatus.loading);
  bool get canSwitchVersion => info?.isGitRepo == true;

  /// True when the SDK sits on a commit the release index doesn't publish
  /// (custom build, fork, or a local commit on top of a release).
  bool get isUnlistedCommit =>
      headHash != null && headHash!.isNotEmpty && installedRelease == null;

  String? get shortHeadHash => headHash == null || headHash!.length < 7
      ? headHash
      : headHash!.substring(0, 7);

  /// Whether HEAD can be compared with the channel tip at all.
  ///
  /// False for a checkout with no HEAD to read, and for a channel the release
  /// index publishes no `current_release` for — master, which rolls. Neither
  /// can be called up to date *or* behind.
  bool get latestKnown => headHash != null && latestRelease != null;

  /// True when the active channel's newest release differs from HEAD.
  bool get updateAvailable => latestKnown && latestRelease!.hash != headHash;

  /// True when the SDK is provably on the channel tip, so an upgrade would
  /// fetch nothing.
  bool get isUpToDate => latestKnown && !updateAvailable;

  FlutterSdkState copyWith({
    FlutterSdkStatus? status,
    FlutterSdkInfo? info,
    List<FlutterRelease>? releases,
    String? browsingChannel,
    bool? versionsLoading,
    List<TrashEntry>? restorable,
    String? errorMessage,
    bool clearError = false,
    String? headHash,
    FlutterRelease? installedRelease,
    FlutterRelease? latestRelease,
    bool clearReleaseMatches = false,
    VersionSource? versionSource,
    SdkPathStatus? pathStatus,
  }) {
    return FlutterSdkState(
      status: status ?? this.status,
      info: info ?? this.info,
      releases: releases ?? this.releases,
      browsingChannel: browsingChannel ?? this.browsingChannel,
      versionsLoading: versionsLoading ?? this.versionsLoading,
      restorable: restorable ?? this.restorable,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      headHash: headHash ?? this.headHash,
      installedRelease: clearReleaseMatches
          ? installedRelease
          : (installedRelease ?? this.installedRelease),
      latestRelease:
          clearReleaseMatches ? latestRelease : (latestRelease ?? this.latestRelease),
      versionSource: versionSource ?? this.versionSource,
      pathStatus: pathStatus ?? this.pathStatus,
    );
  }

  @override
  List<Object?> get props => [
        status,
        info,
        releases,
        browsingChannel,
        versionsLoading,
        restorable,
        errorMessage,
        headHash,
        installedRelease,
        latestRelease,
        versionSource,
        pathStatus,
      ];
}
