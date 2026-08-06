import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../infrastructure/sdk/flutter_locator.dart';
import '../../infrastructure/sdk/sdk_locator.dart';
import '../../infrastructure/sdk/sdk_scan_service.dart';

part 'detected_paths_state.dart';

/// Resolves where the toolchain actually lives, for the Settings > Paths group.
///
/// Uses the same sources as toolchain detection — the locators for the two
/// SDKs, `JAVA_HOME` then PATH for Java — but skips the version probes, since
/// opening Settings shouldn't spawn five processes.
@injectable
class DetectedPathsCubit extends Cubit<DetectedPathsState> {
  DetectedPathsCubit(this._runner, this._locator, this._flutter, this._scanner)
      : super(const DetectedPathsState());

  final CommandRunner _runner;
  final SdkLocator _locator;
  final FlutterLocator _flutter;
  final SdkScanService _scanner;

  Future<void> detect() async {
    if (isClosed) return;
    emit(const DetectedPathsState(isLoading: true));

    // Both SDKs report their *root*, not the executable inside it. `where
    // flutter` answers C:\...\flutter\bin\flutter, which is the tool, not the
    // checkout the app drives — every path setting here means a root.
    final androidSdk = _locator.autoDetectedRoot;
    final flutterSdk = _flutter.autoDetectedRoot;
    final java = await _detectJava();
    if (isClosed) return;

    emit(DetectedPathsState(
      androidSdk: androidSdk,
      java: java,
      flutter: flutterSdk,
    ));

    // Neither the environment nor PATH knew where an SDK is — an install that
    // was never wired into the shell. Look for it on disk rather than
    // reporting "Not found" for something that is sitting right there.
    if (androidSdk == null || flutterSdk == null) {
      await _fillGapsByScanning();
    }
  }

  /// Walks the disk for whichever SDK is still missing, and adopts the first
  /// hit as the detected location.
  Future<void> _fillGapsByScanning() async {
    if (isClosed) return;
    emit(state.copyWith(isScanning: true));
    final android = state.androidSdk == null
        ? await _scanner.findAndroidSdks()
        : const <String>[];
    if (isClosed) return;
    final flutter = state.flutter == null
        ? await _scanner.findFlutterSdks()
        : const <String>[];
    if (isClosed) return;

    emit(state.copyWith(
      androidSdk: state.androidSdk ?? android.firstOrNull,
      flutter: state.flutter ?? flutter.firstOrNull,
      androidCandidates: android,
      flutterCandidates: flutter,
      isScanning: false,
      scanned: true,
    ));
  }

  /// Searches the disk for every install of [kind], for the user to pick from.
  ///
  /// Unlike [detect]'s fallback this always runs, so a second Flutter checkout
  /// can be found even when the first one resolved fine.
  Future<List<String>> scanFor(SdkScanKind kind) async {
    if (isClosed) return const [];
    emit(state.copyWith(isScanning: true));
    final found = switch (kind) {
      SdkScanKind.flutter => await _scanner.findFlutterSdks(),
      SdkScanKind.android => await _scanner.findAndroidSdks(),
    };
    if (isClosed) return found;
    emit(state.copyWith(
      isScanning: false,
      scanned: true,
      flutterCandidates: kind == SdkScanKind.flutter ? found : null,
      androidCandidates: kind == SdkScanKind.android ? found : null,
    ));
    return found;
  }

  /// `JAVA_HOME` if set, else the JDK that owns whichever `java` is on PATH.
  Future<String?> _detectJava() async {
    final home = Platform.environment['JAVA_HOME'];
    if (home != null && home.trim().isNotEmpty) return home.trim();
    final exe = await _which('java');
    return exe == null ? null : javaHomeOf(exe);
  }

  /// Turns `…\jdk-17\bin\java.exe` into `…\jdk-17`.
  ///
  /// PATH resolution finds the launcher, but every other Java path in the app
  /// (and JAVA_HOME itself) names the JDK directory, so the row would otherwise
  /// show two different shapes depending on how it was found.
  static String? javaHomeOf(String executable) {
    final exe = executable.trim();
    if (exe.isEmpty) return null;
    final parent = p.dirname(exe);
    if (p.basename(parent).toLowerCase() != 'bin') return exe;
    return p.dirname(parent);
  }

  Future<String?> _which(String executable) async {
    try {
      return await _runner.which(executable);
    } catch (_) {
      return null;
    }
  }
}
