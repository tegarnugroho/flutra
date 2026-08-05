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
    // Closing the wizard window mid-probe must not emit into a dead cubit.
    if (isClosed) return;
    emit(state.copyWith(loadStatus: LoadStatus.loading, clearError: true));
    try {
      final images = await _repository.listSystemImages();
      final devices = await _repository.listDeviceDefinitions();
      if (isClosed) return;
      emit(state.copyWith(
        loadStatus: LoadStatus.ready,
        images: images,
        devices: devices,
      ));
    } on Failure catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        loadStatus: LoadStatus.failure,
        errorMessage: e.message,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loadStatus: LoadStatus.failure, errorMessage: '$e'));
    }
  }

  // ---- Step navigation -----------------------------------------------------

  void next() {
    if (state.canAdvance && state.step.index < WizardStep.values.last.index) {
      emit(state.copyWith(step: WizardStep.values[state.step.index + 1]));
    }
  }

  /// One step back, except inside the device step, where the device list
  /// falls back to the category picker before the wizard itself moves.
  ///
  /// Returns false when there is nowhere left to go — the caller (the page)
  /// decides what leaving the wizard means.
  bool back() {
    if (state.step == WizardStep.device) {
      if (state.devicePhase == DeviceStepPhase.devices) {
        emit(state.copyWith(devicePhase: DeviceStepPhase.categories));
        return true;
      }
      return false;
    }
    emit(_enteringStep(WizardStep.values[state.step.index - 1]));
    return true;
  }

  void goTo(WizardStep step) => emit(_enteringStep(step));

  /// Stepping onto the device step lands on the list of the selected device's
  /// category, so Back from step 2 restores what the user was looking at.
  CreateEmulatorState _enteringStep(WizardStep step) {
    if (step != WizardStep.device) return state.copyWith(step: step);
    final category = state.selectedDevice?.category ?? state.browsingCategory;
    return state.copyWith(
      step: step,
      browsingCategory: category,
      devicePhase: category == null
          ? DeviceStepPhase.categories
          : DeviceStepPhase.devices,
    );
  }

  // ---- Step 1 phases -------------------------------------------------------

  /// Opens a category's profile list. The search always starts empty so it
  /// never carries a query from another category.
  void openDeviceCategory(DeviceCategory category) => emit(state.copyWith(
    devicePhase: DeviceStepPhase.devices,
    browsingCategory: category,
    deviceQuery: '',
  ));

  void showDeviceCategories() =>
      emit(state.copyWith(devicePhase: DeviceStepPhase.categories));

  void setDeviceQuery(String query) =>
      emit(state.copyWith(deviceQuery: query));

  /// Resets the selection for creating another AVD, keeping the loaded lists.
  void createAnother() => emit(CreateEmulatorState(
        loadStatus: LoadStatus.ready,
        images: state.images,
        devices: state.devices,
      ));

  // ---- Selection -----------------------------------------------------------

  void selectDevice(String deviceId) {
    final suggestedName = _suggestName(deviceId, state.apiLevel);
    emit(state.copyWith(
      deviceId: deviceId,
      name: state.nameEdited ? null : suggestedName,
    ));
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
    if (isClosed) return;
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
      if (isClosed) return;
      emit(state.copyWith(submitting: false, createdName: request.sanitizedName));
    } on Failure catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        submitting: false,
        errorMessage: '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}',
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(submitting: false, errorMessage: '$e'));
    }
  }
}
