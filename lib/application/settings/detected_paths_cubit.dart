import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';
import '../../infrastructure/sdk/sdk_locator.dart';

part 'detected_paths_state.dart';

/// Resolves where the toolchain actually lives, for the Settings > Paths group.
///
/// Uses the same sources as toolchain detection (SDK root from [SdkLocator],
/// `JAVA_HOME` then PATH for Java, PATH for Flutter) but skips the version
/// probes — opening Settings shouldn't spawn five processes.
@injectable
class DetectedPathsCubit extends Cubit<DetectedPathsState> {
  DetectedPathsCubit(this._runner, this._locator)
      : super(const DetectedPathsState());

  final CommandRunner _runner;
  final SdkLocator _locator;

  Future<void> detect() async {
    if (isClosed) return;
    emit(const DetectedPathsState(isLoading: true));
    final java = Platform.environment['JAVA_HOME'] ?? await _which('java');
    final flutter = await _which('flutter');
    if (isClosed) return;
    emit(DetectedPathsState(
      androidSdk: _locator.sdkRoot,
      java: java,
      flutter: flutter,
    ));
  }

  Future<String?> _which(String executable) async {
    try {
      return await _runner.which(executable);
    } catch (_) {
      return null;
    }
  }
}
