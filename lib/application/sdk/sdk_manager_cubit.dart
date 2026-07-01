import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/repositories/sdk_repository.dart';

part 'sdk_manager_state.dart';

/// Drives the SDK Manager: loads the package catalogue and applies filters.
@injectable
class SdkManagerCubit extends Cubit<SdkManagerState> {
  SdkManagerCubit(this._repository) : super(const SdkManagerState());

  final SdkRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: SdkManagerStatus.loading, clearError: true));
    try {
      final packages = await _repository.listPackages();
      emit(state.copyWith(
        status: SdkManagerStatus.ready,
        packages: packages,
      ));
    } on Failure catch (e) {
      emit(state.copyWith(
        status: SdkManagerStatus.failure,
        errorMessage:
            '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}',
      ));
    } catch (e) {
      emit(state.copyWith(
          status: SdkManagerStatus.failure, errorMessage: '$e'));
    }
  }

  void setQuery(String query) => emit(state.copyWith(query: query));

  void setCategory(PackageCategory? category) =>
      emit(state.copyWith(category: category, clearCategory: category == null));

  void toggleUpdatesOnly(bool value) =>
      emit(state.copyWith(updatesOnly: value));

  void toggleInstalledOnly(bool value) =>
      emit(state.copyWith(installedOnly: value));

  /// Starts installing/updating [path]; caller streams the returned handle.
  Future<RunningCommand> install(String path) => _repository.install(path);

  /// Starts uninstalling [path]; caller streams the returned handle.
  Future<RunningCommand> uninstall(String path) => _repository.uninstall(path);
}
