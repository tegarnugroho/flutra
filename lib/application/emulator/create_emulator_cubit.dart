import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/error/failures.dart';
import '../../domain/entities/avd_create_request.dart';
import '../../domain/entities/device_definition.dart';
import '../../domain/entities/system_image.dart';
import '../../domain/repositories/emulator_repository.dart';

part 'create_emulator_state.dart';

/// Backs the Create Emulator wizard: loads options, tracks the selection, and
/// derives the valid choices for each step from the installed system images.
@injectable
class CreateEmulatorCubit extends Cubit<CreateEmulatorState> {
  CreateEmulatorCubit(this._repository) : super(const CreateEmulatorState());

  final EmulatorRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(loadStatus: LoadStatus.loading, clearError: true));
    try {
      final images = await _repository.listSystemImages();
      final devices = await _repository.listDeviceDefinitions();
      emit(state.copyWith(
        loadStatus: LoadStatus.ready,
        images: images,
        devices: devices,
      ));
    } on Failure catch (e) {
      emit(state.copyWith(
        loadStatus: LoadStatus.failure,
        errorMessage: e.message,
      ));
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, errorMessage: '$e'));
    }
  }

  // ---- Step navigation -----------------------------------------------------

  void next() {
    if (state.canAdvance && state.step.index < WizardStep.values.last.index) {
      emit(state.copyWith(step: WizardStep.values[state.step.index + 1]));
    }
  }

  void back() {
    if (state.step.index > 0) {
      emit(state.copyWith(step: WizardStep.values[state.step.index - 1]));
    }
  }

  void goTo(WizardStep step) => emit(state.copyWith(step: step));

  /// Resets the selection for creating another AVD, keeping the loaded lists.
  void createAnother() => emit(CreateEmulatorState(
        loadStatus: LoadStatus.ready,
        images: state.images,
        devices: state.devices,
      ));

  // ---- Selection -----------------------------------------------------------

  void selectDevice(String deviceId) {
    final suggestedName = _suggestName(deviceId, state.apiLevel);
    emit(state.copyWith(deviceId: deviceId, name: state.nameEdited ? null : suggestedName));
  }

  void selectApiLevel(int api) {
    // Reset dependent choices that may no longer be valid.
    emit(state.copyWith(
      apiLevel: api,
      clearTag: true,
      clearAbi: true,
      name: state.nameEdited ? null : _suggestName(state.deviceId, api),
    ));
  }

  void selectTag(String tag) =>
      emit(state.copyWith(tag: tag, clearAbi: true));

  void selectAbi(String abi) => emit(state.copyWith(abi: abi));

  void setName(String name) =>
      emit(state.copyWith(name: name, nameEdited: true));

  void updateConfig(EmulatorConfig config) =>
      emit(state.copyWith(config: config));

  String? _suggestName(String? deviceId, int? api) {
    if (deviceId == null || api == null) return null;
    final device = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return '${device}_API_$api';
  }

  // ---- Submit --------------------------------------------------------------

  Future<void> submit() async {
    final image = state.selectedImage;
    if (image == null || state.deviceId == null || state.name.trim().isEmpty) {
      emit(state.copyWith(errorMessage: 'Please complete all steps first.'));
      return;
    }
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final request = AvdCreateRequest(
        name: state.name,
        systemImage: image,
        deviceId: state.deviceId!,
        ramMb: state.config.ramMb,
        vmHeapMb: state.config.vmHeapMb,
        internalStorageMb: state.config.internalStorageMb,
        sdCardMb: state.config.sdCardMb,
        gpuMode: state.config.gpuMode,
        enableCamera: state.config.enableCamera,
        cpuCores: state.config.cpuCores,
      );
      await _repository.createAvd(request);
      emit(state.copyWith(submitting: false, createdName: request.sanitizedName));
    } on Failure catch (e) {
      emit(state.copyWith(
        submitting: false,
        errorMessage: '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}',
      ));
    } catch (e) {
      emit(state.copyWith(submitting: false, errorMessage: '$e'));
    }
  }
}
