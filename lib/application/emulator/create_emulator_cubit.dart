import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_result.dart';
import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/avd_create_request.dart';
import '../../domain/entities/device_definition.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/entities/system_image.dart';
import '../../domain/repositories/emulator_repository.dart';
import '../../domain/repositories/sdk_repository.dart';

part 'create_emulator_state.dart';

/// Backs the Create Emulator wizard: loads options, tracks the selection, and
/// derives the valid choices for each step from the installed system images.
@injectable
class CreateEmulatorCubit extends Cubit<CreateEmulatorState> {
  CreateEmulatorCubit(this._repository, this._sdk)
    : super(const CreateEmulatorState());

  final EmulatorRepository _repository;
  final SdkRepository _sdk;

  /// sdkmanager reports "  Downloading ... 42%" style lines.
  static final RegExp _progressPattern = RegExp(r'(\d{1,3})\s*%');

  /// The install currently streaming, so Cancel can reach it.
  RunningCommand? _install;
  bool _cancelled = false;

  Future<void> load() async {
    // Closing the wizard window mid-probe must not emit into a dead cubit.
    if (isClosed) return;
    emit(state.copyWith(loadStatus: LoadStatus.loading, clearError: true));
    try {
      // Fire all three before awaiting any: `sdkmanager --list` and
      // `avdmanager list device` each boot a JVM, and the first also fetches
      // the remote repository index. Chained, the wizard waits for their sum;
      // started together it waits for the slowest.
      final packagesFuture = _sdk.listPackages();
      final imagesFuture = _repository.listSystemImages();
      final devicesFuture = _repository.listDeviceDefinitions();

      final options = _mergeCatalogue(
        await packagesFuture,
        await imagesFuture,
      );
      final devices = await devicesFuture;
      if (isClosed) return;
      emit(state.copyWith(
        loadStatus: LoadStatus.ready,
        options: options,
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

  /// Re-reads the catalogue after an install, to confirm the package landed.
  Future<List<ImageOption>> _reloadCatalogue() async {
    final packagesFuture = _sdk.listPackages();
    final imagesFuture = _repository.listSystemImages();
    return _mergeCatalogue(await packagesFuture, await imagesFuture);
  }

  /// Every system-image package sdkmanager knows about, merged with what is
  /// actually on disk.
  ///
  /// sdkmanager is the catalogue — it is the only source that lists images the
  /// user has *not* downloaded. The on-disk scan is layered on top because an
  /// image can be present while sdkmanager's cached list still calls it
  /// available, and the wizard must not offer to re-download it.
  static List<ImageOption> _mergeCatalogue(
    List<SdkPackage> packages,
    List<SystemImage> onDisk,
  ) {
    final byPath = <String, ImageOption>{};
    for (final package in packages) {
      final option = ImageOption.tryParse(
        package.path,
        installed: package.isInstalled,
      );
      if (option != null) byPath[option.packagePath] = option;
    }
    for (final image in onDisk) {
      final existing = byPath[image.packagePath];
      byPath[image.packagePath] =
          existing?.copyWith(installed: true) ??
          ImageOption(
            packagePath: image.packagePath,
            apiLevel: image.apiLevel,
            tag: image.tag,
            abi: image.abi,
            installed: true,
          );
    }
    return byPath.values.toList();
  }

  void toggleOlderApis() =>
      emit(state.copyWith(showOlderApis: !state.showOlderApis));

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
    options: state.options,
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

  /// Downloads the chosen system image if it is missing, then creates the AVD.
  ///
  /// The download is deferred to here on purpose: steps 2–4 stay browsable
  /// whether or not a package is on disk, and the one long wait happens once,
  /// where the user has already committed.
  Future<void> submit() async {
    final option = state.selectedOption;
    if (option == null || state.deviceId == null || state.name.trim().isEmpty) {
      emit(state.copyWith(errorMessage: 'Please complete all steps first.'));
      return;
    }
    if (isClosed) return;
    _cancelled = false;
    emit(state.copyWith(submitting: true, clearError: true));

    try {
      if (!option.installed) {
        final installed = await _downloadImage(option);
        if (_cancelled || isClosed) return _resetToIdle();
        if (!installed) return;
      }

      if (isClosed) return;
      emit(state.copyWith(
        installPhase: InstallPhase.creating,
        clearProgress: true,
      ));
      final request = AvdCreateRequest(
        name: state.name,
        systemImage: option.toSystemImage(),
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
      emit(state.copyWith(
        submitting: false,
        installPhase: InstallPhase.idle,
        clearProgress: true,
        createdName: request.sanitizedName,
      ));
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    }
  }

  /// Runs sdkmanager for [option] and confirms the package landed.
  ///
  /// Returns false when it failed — the error is already on the state, and the
  /// footer offers Retry without losing any of the wizard's choices.
  Future<bool> _downloadImage(ImageOption option) async {
    emit(state.copyWith(
      installPhase: InstallPhase.downloading,
      installProgress: 0,
    ));

    // TODO(licenses): SdkRepository.install answers "y" to every license
    // prompt (see `_startWithAutoYes`), which is how the SDK manager screen
    // installs too. Routing the wizard through a separate, prompting flow would
    // mean a second install path — surface the licenses explicitly here once
    // the repository can install without auto-accepting.
    final command = await _sdk.install(option.packagePath);
    _install = command;
    final sub = command.output.listen(_onInstallOutput);
    final result = await command.result;
    await sub.cancel();
    _install = null;
    if (_cancelled || isClosed) return false;

    if (!result.isSuccess) {
      _fail(
        'Could not install ${option.packagePath}.\n'
        '${_lastMeaningfulLine(result.stderr, result.stdout)}',
      );
      return false;
    }

    // Verify rather than trust the exit code: sdkmanager exits 0 on some
    // no-op paths, and creating an AVD against a missing image fails later
    // with a far more confusing message.
    emit(state.copyWith(
      installPhase: InstallPhase.verifying,
      clearProgress: true,
    ));
    final options = await _reloadCatalogue();
    if (isClosed) return false;
    final fresh = options.firstWhere(
      (o) => o.packagePath == option.packagePath,
      orElse: () => option,
    );
    emit(state.copyWith(options: options));
    if (!fresh.installed) {
      _fail(
        'The system image finished downloading but is not installed.\n'
        'Try installing ${option.packagePath} from the SDK manager.',
      );
      return false;
    }
    return true;
  }

  void _onInstallOutput(CommandOutputLine line) {
    if (isClosed) return;
    final text = line.text;
    final lower = text.toLowerCase();
    // sdkmanager narrates its own phases; mirror them so the footer says
    // something truer than a generic "working".
    final phase = lower.contains('unzip') || lower.contains('install')
        ? InstallPhase.installing
        : lower.contains('download') || lower.contains('fetch')
        ? InstallPhase.downloading
        : state.installPhase;

    final match = _progressPattern.firstMatch(text);
    emit(state.copyWith(
      installPhase: phase,
      installProgress: match == null
          ? null
          : (int.tryParse(match.group(1)!) ?? 0).clamp(0, 100) / 100,
      clearProgress: match == null,
    ));
  }

  /// Aborts an in-flight download and returns the wizard to its idle state,
  /// selections intact.
  void cancelInstall() {
    _cancelled = true;
    _install?.cancel();
    _install = null;
    _resetToIdle();
  }

  void _resetToIdle() {
    if (isClosed) return;
    emit(state.copyWith(
      submitting: false,
      installPhase: InstallPhase.idle,
      clearProgress: true,
    ));
  }

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(
      submitting: false,
      installPhase: InstallPhase.idle,
      clearProgress: true,
      errorMessage: message,
    ));
  }

  /// The most useful line to show the user: the tail of stderr, or of stdout
  /// when the tool wrote its complaint there instead.
  static String _lastMeaningfulLine(String stderr, String stdout) {
    for (final source in [stderr, stdout]) {
      final lines = source
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return lines.last;
    }
    return 'sdkmanager gave no output.';
  }
}
