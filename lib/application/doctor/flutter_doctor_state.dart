part of 'flutter_doctor_cubit.dart';

enum DoctorRunStatus { initial, running, done, failure }

/// Immutable state for the Flutter Doctor screen.
class FlutterDoctorState extends Equatable {
  const FlutterDoctorState({
    this.status = DoctorRunStatus.initial,
    this.report,
    this.errorMessage,
  });

  final DoctorRunStatus status;
  final DoctorReport? report;
  final String? errorMessage;

  bool get isRunning => status == DoctorRunStatus.running;

  FlutterDoctorState copyWith({
    DoctorRunStatus? status,
    DoctorReport? report,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FlutterDoctorState(
      status: status ?? this.status,
      report: report ?? this.report,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, report, errorMessage];
}
