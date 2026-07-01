import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/flutter_sdk_info.dart';
import '../../domain/repositories/flutter_repository.dart';

part 'flutter_sdk_state.dart';

/// Drives the Flutter SDK screen: reads the active SDK and switches
/// channels/versions.
@injectable
class FlutterSdkCubit extends Cubit<FlutterSdkState> {
  FlutterSdkCubit(this._repository) : super(const FlutterSdkState());

  final FlutterRepository _repository;

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(status: FlutterSdkStatus.loading, clearError: true));
    try {
      final info = await _repository.getSdkInfo();
      if (isClosed) return;
      // Default browsing to the active channel, or stable if it's unknown.
      final channel = info.isKnownChannel ? info.channel : 'stable';
      final versions = await _versionsFor(channel);
      if (isClosed) return;
      emit(state.copyWith(
        status: FlutterSdkStatus.ready,
        info: info,
        versions: versions,
        browsingChannel: channel,
        versionsLoading: false,
      ));
    } on ExecutableNotFoundFailure {
      // No Flutter on PATH — offer to install one.
      if (!isClosed) emit(state.copyWith(status: FlutterSdkStatus.notInstalled));
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    }
  }

  Future<RunningCommand> installSdk(String directory, String ref) =>
      _repository.installSdk(directory, ref);

  Future<List<String>> listInstallableVersions(String channel) =>
      _repository.listInstallableVersions(channel);

  Future<void> addToPath(String sdkDir) => _repository.addSdkToPath(sdkDir);

  Future<void> uninstall() async {
    final path = state.info?.sdkPath;
    if (path == null) return;
    try {
      await _repository.uninstallSdk(path);
      await load();
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    }
  }

  /// Switches the browsed channel and reloads its version list (does NOT change
  /// the active SDK channel).
  Future<void> browseChannel(String channel) async {
    if (isClosed || channel == state.browsingChannel) return;
    emit(state.copyWith(browsingChannel: channel, versionsLoading: true));
    final versions = await _versionsFor(channel);
    if (isClosed) return;
    emit(state.copyWith(versions: versions, versionsLoading: false));
  }

  Future<List<String>> _versionsFor(String channel) async {
    try {
      return await _repository.listVersions(channel);
    } on Failure {
      return const [];
    }
  }

  Future<RunningCommand> switchChannel(String channel) =>
      _repository.switchChannel(channel);

  Future<RunningCommand> upgrade() => _repository.upgrade();

  Future<RunningCommand> resetToStable() => _repository.resetToStable();

  Future<RunningCommand> switchVersion(String version) =>
      _repository.switchVersion(version);

  Future<List<String>> changelog(String version, String? previousVersion) =>
      _repository.changelog(version, previousVersion);

  Future<void> openReleasePage(String version) =>
      _repository.openReleasePage(version);

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(status: FlutterSdkStatus.failure, errorMessage: message));
  }
}
