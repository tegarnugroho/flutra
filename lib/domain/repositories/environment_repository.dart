import '../entities/environment_snapshot.dart';

/// Detects the state of the local Android / Flutter toolchain.
///
/// Implemented in the infrastructure layer by probing the actual command-line
/// tools; the presentation layer depends only on this abstraction.
abstract class EnvironmentRepository {
  /// Runs full detection and returns an aggregate [EnvironmentSnapshot].
  ///
  /// Never throws for individual tool failures — a missing or broken tool is
  /// reported as a failing [ToolStatus] within the snapshot.
  Future<EnvironmentSnapshot> detect();
}
