import '../../core/command/command_runner.dart';
import '../entities/sdk_package.dart';

/// Manages SDK components via the `sdkmanager` command-line tool.
abstract class SdkRepository {
  /// Lists every package known to sdkmanager (installed, available, updatable).
  Future<List<SdkPackage>> listPackages();

  /// Installs (or updates) the package at [path]. Licenses are auto-accepted.
  ///
  /// Returns the live process so the UI can stream progress and cancel.
  Future<RunningCommand> install(String path);

  /// Uninstalls the installed package at [path].
  Future<RunningCommand> uninstall(String path);

  /// Runs `sdkmanager --licenses`, auto-answering "y" to every prompt.
  Future<RunningCommand> acceptAllLicenses();

  /// Updates every installed package that has a newer version available
  /// (`sdkmanager --update`). Streaming handle.
  Future<RunningCommand> updateAll();
}
