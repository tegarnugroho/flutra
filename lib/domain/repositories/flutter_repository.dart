import '../../core/command/command_runner.dart';
import '../entities/device.dart';
import '../entities/flutter_sdk_info.dart';
import '../entities/version_switch.dart';

/// Runs Flutter tooling commands.
abstract class FlutterRepository {
  /// Lists all Flutter targets via `flutter devices` (Android, desktop, web).
  Future<List<Device>> listDevices();

  /// Reads the active Flutter SDK version, channel and path.
  Future<FlutterSdkInfo> getSdkInfo();

  /// Lists release versions for [channel] from the local git tags, newest
  /// first. Empty when the SDK is not a git repo.
  ///
  /// This is the offline fallback for the official release index; see
  /// [FlutterReleasesService].
  Future<List<String>> listVersions(String channel);

  /// The commit the local SDK checkout is on (`git rev-parse HEAD`), or null
  /// when there is no SDK or it is not a git checkout.
  Future<String?> sdkHeadHash();

  /// Switches the SDK to [channel] (e.g. "stable"). Streaming handle.
  /// See [upgrade] for [stashLocalChanges].
  Future<RunningCommand> switchChannel(String channel,
      {bool stashLocalChanges = false});

  /// Lists uncommitted changes in the SDK checkout as `git status --porcelain`
  /// lines (e.g. `M pubspec.lock`). `flutter upgrade` refuses to run while any
  /// exist. Empty when the SDK is clean or is not a git repo.
  Future<List<String>> localChanges();

  /// Upgrades the current channel to its latest build. Streaming handle.
  ///
  /// With [stashLocalChanges], uncommitted SDK changes are moved to a git stash
  /// first (recoverable with `git stash pop`) so the upgrade is not blocked.
  Future<RunningCommand> upgrade({bool stashLocalChanges = false});

  /// Returns the SDK to the official `stable` channel and upgrades it. Useful
  /// after a version checkout left the SDK on an "unknown"/user branch.
  /// See [upgrade] for [stashLocalChanges].
  Future<RunningCommand> resetToStable({bool stashLocalChanges = false});

  /// Points the SDK's `origin` remote at the official Flutter repository,
  /// clearing the "not a standard remote" doctor warning.
  Future<void> fixUpstreamRemote();

  /// Moves the SDK to release [version], reporting one [VersionSwitchEvent] per
  /// stage until it succeeds or fails.
  ///
  /// [channel] is the channel the release is published on ("stable"/"beta"),
  /// taken from the release index — see [switchChannelFor]. The tag is checked
  /// out *onto* that branch, which is then pointed at `origin/<channel>`, so
  /// Flutter keeps reporting an official channel instead of "[user-branch]".
  ///
  /// A dirty checkout is stashed automatically (see [kSwitchStashMessage]) and
  /// never restored; the outcome says so. Every failure of a step arrives as a
  /// [VersionSwitchFailed] event, after the SDK has been rolled back — only a
  /// missing `git` reaches the caller as a stream error.
  Stream<VersionSwitchEvent> switchVersion(String version,
      {required String channel});

  /// Whether the SDK already sits on [version] *and* on the [channel] branch,
  /// which makes a switch a no-op.
  Future<bool> isOnVersion(String version, String channel);

  /// Returns the commit subjects introduced in [version] relative to
  /// [previousVersion] (a de-facto changelog from the SDK git history). When
  /// [previousVersion] is null, returns the most recent commits at that tag.
  Future<List<String>> changelog(String version, String? previousVersion);

  /// Opens the GitHub release page for [version] in the default browser.
  Future<void> openReleasePage(String version);

  /// Opens pull request [number] of flutter/flutter in the default browser.
  Future<void> openPullRequest(int number);

  /// Clones the Flutter SDK into [directory] at [ref] (a channel name like
  /// "stable" or a version tag like "3.24.0"). Streaming handle. Used when no
  /// Flutter SDK is installed yet.
  Future<RunningCommand> installSdk(String directory, String ref);

  /// Fetches the official installable versions for [channel] from Flutter's
  /// release index (network). Empty on failure.
  Future<List<String>> listInstallableVersions(String channel);

  /// Appends `<sdkDir>/bin` to the user's PATH (Windows). Requires an app
  /// restart to take effect.
  Future<void> addSdkToPath(String sdkDir);

  /// Whether `<sdkDir>/bin` is already on PATH — either the one this process
  /// inherited, or the user-level one a new terminal would see.
  Future<bool> isSdkOnPath(String sdkDir);

  /// Permanently deletes the Flutter SDK at [sdkPath].
  Future<void> uninstallSdk(String sdkPath);
}
