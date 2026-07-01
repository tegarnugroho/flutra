import '../entities/doctor_report.dart';

/// Runs Flutter tooling commands.
abstract class FlutterRepository {
  /// Runs `flutter doctor -v` and returns the parsed report.
  Future<DoctorReport> runDoctor();
}
