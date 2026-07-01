import '../../core/command/command_runner.dart';
import '../entities/avd.dart';
import '../entities/avd_create_request.dart';
import '../entities/device_definition.dart';
import '../entities/system_image.dart';

/// Manages Android Virtual Devices via `avdmanager` and `emulator`.
abstract class EmulatorRepository {
  /// Lists all AVDs, annotated with their running state.
  Future<List<Avd>> listAvds();

  /// Installed system images that can back a new AVD.
  Future<List<SystemImage>> listSystemImages();

  /// Available hardware device profiles.
  Future<List<DeviceDefinition>> listDeviceDefinitions();

  /// Creates and configures a new AVD. Throws a [Failure] on error.
  Future<void> createAvd(AvdCreateRequest request);

  /// Permanently deletes an AVD.
  Future<void> deleteAvd(String name);

  /// Clears user data for an AVD (next boot starts fresh).
  Future<void> wipeData(String name);

  /// Duplicates an existing AVD under a new [newName].
  Future<void> duplicateAvd(String source, String newName);

  /// Launches the emulator for [name], returning the live process handle so the
  /// UI can stream console output and stop it.
  Future<RunningCommand> launch(String name, LaunchOptions options);

  /// Requests a graceful shutdown of the running emulator for [name].
  Future<void> stop(String name);
}
