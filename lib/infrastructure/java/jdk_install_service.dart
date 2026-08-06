import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../core/platform/platform_service.dart';
import '../../domain/entities/jdk_release.dart';
import 'jdk_catalog_service.dart';

/// Which part of an install is running, for the progress line.
enum JdkInstallStage {
  downloading,
  verifying,
  extracting,
  done,
  failed;

  String get label => switch (this) {
    JdkInstallStage.downloading => 'Downloading…',
    JdkInstallStage.verifying => 'Verifying…',
    JdkInstallStage.extracting => 'Extracting…',
    JdkInstallStage.done => 'Installed',
    JdkInstallStage.failed => 'Failed',
  };
}

/// One step of an install, as it happens.
class JdkInstallEvent {
  const JdkInstallEvent({
    required this.stage,
    this.progress,
    this.installedPath,
    this.error,
  });

  final JdkInstallStage stage;

  /// 0–1 while downloading, null when the server sent no length and for the
  /// stages that cannot report one.
  final double? progress;

  /// The JDK root, once [stage] is [JdkInstallStage.done].
  final String? installedPath;

  final String? error;
}

/// Downloads a JDK, checks it, and unpacks it into a folder this app owns.
///
/// The archive rather than the installer, and a managed folder rather than
/// Program Files: no elevation is needed, nothing is registered with Windows,
/// and uninstalling is deleting a directory.
@lazySingleton
class JdkInstallService {
  JdkInstallService(this._catalog, this._runner, this._platform);

  final JdkCatalogService _catalog;
  final CommandRunner _runner;
  final PlatformService _platform;

  static final Logger _log = Logger('JdkInstallService');

  /// A 200 MB download over a slow line still has to be allowed to finish.
  static const _downloadTimeout = Duration(minutes: 30);

  final Map<String, CancelToken> _cancels = {};

  /// Where managed JDKs live: `<app support>/jdks/<vendor>-<version>`.
  Future<Directory> managedRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'jdks'));
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  /// Runs the whole install, reporting each stage.
  ///
  /// Every failure arrives as a [JdkInstallStage.failed] event rather than an
  /// exception: this is driven from a dialog, and a throw there would be a
  /// crash where the user wanted a message.
  Stream<JdkInstallEvent> install(JdkRelease release) async* {
    final cancel = CancelToken();
    _cancels[release.downloadUrl] = cancel;

    Directory? staging;
    try {
      final root = await managedRoot();
      final target = Directory(p.join(root.path, release.installFolderName));
      if (target.existsSync()) {
        // Already there: nothing to download, and overwriting a JDK someone may
        // be building against is not this feature's business.
        yield JdkInstallEvent(
          stage: JdkInstallStage.done,
          installedPath: target.path,
        );
        return;
      }

      staging = await Directory(
        p.join(root.path, '.staging-${release.installFolderName}'),
      ).create(recursive: true);
      final archive = File(p.join(staging.path, release.fileName));

      // ---- download
      yield const JdkInstallEvent(
        stage: JdkInstallStage.downloading,
        progress: 0,
      );
      final expected = await _catalog.resolveChecksum(release);
      yield* _download(release, archive, cancel);

      // ---- verify
      if (expected != null) {
        yield const JdkInstallEvent(stage: JdkInstallStage.verifying);
        final actual = await sha256OfFile(archive);
        if (actual.toLowerCase() != expected.toLowerCase()) {
          yield const JdkInstallEvent(
            stage: JdkInstallStage.failed,
            error:
                'The download did not match its published checksum, so it was '
                'discarded. Try again.',
          );
          return;
        }
      } else {
        // Not fatal, but worth recording: the vendor gave us nothing to check.
        _log.warning('No checksum published for ${release.fileName}.');
      }

      // ---- extract
      yield const JdkInstallEvent(stage: JdkInstallStage.extracting);
      final unpacked = Directory(p.join(staging.path, 'unpacked'))
        ..createSync(recursive: true);
      await _extract(archive, unpacked);

      final home = findJdkHome(unpacked.path);
      if (home == null) {
        yield const JdkInstallEvent(
          stage: JdkInstallStage.failed,
          error: 'The archive did not contain a JDK (no bin folder inside).',
        );
        return;
      }

      await Directory(home).rename(target.path);
      yield JdkInstallEvent(
        stage: JdkInstallStage.done,
        installedPath: target.path,
      );
    } on Failure catch (e) {
      yield JdkInstallEvent(stage: JdkInstallStage.failed, error: e.message);
    } catch (e) {
      yield JdkInstallEvent(
        stage: JdkInstallStage.failed,
        error: cancel.isCancelled ? 'Cancelled.' : '$e',
      );
    } finally {
      _cancels.remove(release.downloadUrl);
      // The staging folder holds a 200 MB archive; it never outlives the run.
      try {
        if (staging != null && staging.existsSync()) {
          staging.deleteSync(recursive: true);
        }
      } catch (e) {
        _log.fine('could not clear staging: $e');
      }
    }
  }

  /// Stops an install in flight. The partial download goes with the staging
  /// folder.
  void cancel(JdkRelease release) {
    _cancels[release.downloadUrl]?.cancel('cancelled by the user');
  }

  bool isRunning(JdkRelease release) =>
      _cancels.containsKey(release.downloadUrl);

  Stream<JdkInstallEvent> _download(
    JdkRelease release,
    File target,
    CancelToken cancel,
  ) async* {
    final controller = StreamController<JdkInstallEvent>();
    final dio = Dio(BaseOptions(receiveTimeout: _downloadTimeout));

    final done = dio
        .download(
          release.downloadUrl,
          target.path,
          cancelToken: cancel,
          onReceiveProgress: (received, total) {
            if (controller.isClosed) return;
            controller.add(
              JdkInstallEvent(
                stage: JdkInstallStage.downloading,
                progress: total > 0 ? received / total : null,
              ),
            );
          },
        )
        .whenComplete(controller.close);

    yield* controller.stream;
    await done;
  }

  /// Unpacks with the OS's own extractor.
  ///
  /// `tar` has shipped in Windows since 1803 and reads zip; a pure-Dart unzip
  /// of a 200 MB archive is minutes of work on the UI isolate.
  Future<void> _extract(File archive, Directory destination) async {
    final (command, arguments) = switch (_platform.operatingSystem) {
      'windows' => ('tar', ['-xf', archive.path, '-C', destination.path]),
      _ => ('unzip', ['-q', archive.path, '-d', destination.path]),
    };
    final result = await _runner.run(
      command,
      arguments,
      timeout: const Duration(minutes: 10),
    );
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Could not unpack the archive.',
        exitCode: result.exitCode,
        output: result.combinedOutput.trim(),
      );
    }
  }

  /// SHA-256 of [file], read in chunks so a 200 MB archive never lands in
  /// memory whole.
  static Future<String> sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// The JDK root inside an unpacked archive.
  ///
  /// Both vendors wrap everything in one top-level folder, but neither promises
  /// to: this looks at the extraction root first, then one level down.
  static String? findJdkHome(String unpackedRoot) {
    bool isHome(String directory) =>
        Directory(p.join(directory, 'bin')).existsSync();

    if (isHome(unpackedRoot)) return unpackedRoot;
    try {
      for (final child in Directory(unpackedRoot).listSync()) {
        if (child is Directory && isHome(child.path)) return child.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
