import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/error/failures.dart';
import '../../domain/entities/doctor_report.dart';
import '../../domain/repositories/flutter_repository.dart';

part 'flutter_doctor_state.dart';

/// Runs `flutter doctor -v` and exposes the parsed report.
@injectable
class FlutterDoctorCubit extends Cubit<FlutterDoctorState> {
  FlutterDoctorCubit(this._repository) : super(const FlutterDoctorState());

  final FlutterRepository _repository;

  Future<void> run() async {
    if (isClosed) return;
    emit(state.copyWith(status: DoctorRunStatus.running, clearError: true));
    try {
      final report = await _repository.runDoctor();
      if (isClosed) return;
      emit(state.copyWith(status: DoctorRunStatus.done, report: report));
    } on Failure catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        status: DoctorRunStatus.failure,
        errorMessage:
            '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}',
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
          status: DoctorRunStatus.failure, errorMessage: '$e'));
    }
  }
}
