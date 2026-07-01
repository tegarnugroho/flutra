import '../../core/command/command_runner.dart';
import '../entities/device.dart';
import '../entities/doctor_report.dart';
import '../entities/flutter_sdk_info.dart';

/// Runs Flutter tooling commands.
abstract class FlutterRepository {
  /// Runs `flutter doctor -v` and returns the parsed report.
  Future<DoctorReport> runDoctor();

  /// Lists all Flutter targets via `flutter devices` (Android, desktop, web).
  Future<List<Device>> listDevices();

  /// Reads the active Flutter SDK version, channel and path.
  Future<FlutterSdkInfo> getSdkInfo();

  /// Lists installable release versions for [channel] (git tags reachable from
  /// that channel branch), newest first. Empty when the SDK is not a git repo.
  Future<List<String>> listVersions(String channel);

  /// Switches the SDK to [channel] (e.g. "stable"). Streaming handle.
  Future<RunningCommand> switchChannel(String channel);

  /// Upgrades the current channel to its latest build. Streaming handle.
  Future<RunningCommand> upgrade();

  /// Returns the SDK to the official `stable` channel and upgrades it. Useful
  /// after a version checkout left the SDK on an "unknown"/user branch.
  Future<RunningCommand> resetToStable();

  /// Points the SDK's `origin` remote at the official Flutter repository,
  /// clearing the "not a standard remote" doctor warning.
  Future<void> fixUpstreamRemote();

  /// Checks out release [version] (a git tag) and rebuilds the tool. Streaming.
  Future<RunningCommand> switchVersion(String version);

  /// Returns the commit subjects introduced in [version] relative to
  /// [previousVersion] (a de-facto changelog from the SDK git history). When
  /// [previousVersion] is null, returns the most recent commits at that tag.
  Future<List<String>> changelog(String version, String? previousVersion);

  /// Opens the GitHub release page for [version] in the default browser.
  Future<void> openReleasePage(String version);

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

  /// Permanently deletes the Flutter SDK at [sdkPath].
  Future<void> uninstallSdk(String sdkPath);
}
