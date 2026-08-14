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
import 'archive_format.dart';
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

      // A run killed mid-download leaves this behind. Clearing it is what makes
      // Retry a fresh download rather than a second attempt at unpacking
      // whatever the last one managed to write.
      final previous = Directory(
        p.join(root.path, '.staging-${release.installFolderName}'),
      );
      if (previous.existsSync()) previous.deleteSync(recursive: true);
      staging = await previous.create(recursive: true);
      final archive = File(p.join(staging.path, release.fileName));

      // ---- download
      yield const JdkInstallEvent(
        stage: JdkInstallStage.downloading,
        progress: 0,
      );
      final expected = await _catalog.resolveChecksum(release);
      yield* _download(release, archive, cancel);

      // ---- verify
      // Length before digest: a connection that dropped at 60% is the common
      // failure, and "stopped early" says more than "did not match its
      // checksum" about what to do next.
      final sizeError = checkDownloadedSize(
        actual: archive.existsSync() ? archive.lengthSync() : 0,
        expected: release.sizeBytes,
      );
      if (sizeError != null) {
        yield JdkInstallEvent(
          stage: JdkInstallStage.failed,
          error: sizeError,
        );
        return;
      }

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
          error: 'The archive did not contain a JDK (no bin/java inside).',
        );
        return;
      }

      // Modes first, then prove it runs. Checked here, while everything is
      // still in staging, so a JDK that cannot start never reaches the managed
      // folder and Retry has nothing to clean up.
      await _restoreExecutableBits(home);
      final launchError = await _validate(home);
      if (launchError != null) {
        yield JdkInstallEvent(
          stage: JdkInstallStage.failed,
          error: launchError,
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
    } on FileSystemException catch (e) {
      // Out of space, or a folder this process may not write. Neither is
      // something Retry fixes, so the message has to say which it was.
      yield JdkInstallEvent(
        stage: JdkInstallStage.failed,
        error:
            'Could not write to disk: ${e.osError?.message ?? e.message}. '
            'Check the free space and permissions on the app data folder.',
      );
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

    // The resolved URL and file name, because which container a vendor serves
    // depends on the os/arch the catalogue asked for — and when an install
    // fails to unpack, that pair is the first thing worth seeing.
    _log.info(
      'Downloading ${release.fileName} for ${_platform.operatingSystem}/'
      '${_platform.architecture} from ${release.downloadUrl}',
    );

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

  /// Unpacks with the OS's own extractor, choosing it by what the archive
  /// actually is.
  ///
  /// The format follows the archive, never the host: both vendors serve `.zip`
  /// to Windows and `.tar.gz` to Linux and macOS, so keying the extractor off
  /// the running platform unpacks the wrong container the moment the app leaves
  /// Windows. It is read from the file's signature bytes — see
  /// [detectArchiveFormat] — because the name is metadata and the bytes are the
  /// thing being unpacked.
  ///
  /// Always an external process: `tar` has shipped in Windows since 1803 and
  /// reads both zip and gzip, and a pure-Dart unpack of a 200 MB archive is
  /// minutes of work on the UI isolate. The process is its own, so nothing here
  /// blocks a frame.
  Future<void> _extract(File archive, Directory destination) async {
    final format = await detectArchiveFormat(archive);
    _log.info(
      'Unpacking ${p.basename(archive.path)} as ${format.name} '
      '(${_platform.operatingSystem}).',
    );

    final (command, arguments) = switch (format) {
      // bsdtar on Windows reads zip; elsewhere tar does not, so unzip it is.
      ArchiveFormat.zip when _platform.isWindows => (
        'tar',
        ['-xf', archive.path, '-C', destination.path],
      ),
      ArchiveFormat.zip => (
        'unzip',
        ['-q', archive.path, '-d', destination.path],
      ),
      ArchiveFormat.tarGz => (
        'tar',
        ['-xzf', archive.path, '-C', destination.path],
      ),
      ArchiveFormat.tar => (
        'tar',
        ['-xf', archive.path, '-C', destination.path],
      ),
      // Not a process failure: nothing was run. The file that arrived is not
      // an archive at all, which is what a CDN error page served with a 200
      // looks like from here.
      ArchiveFormat.unknown => throw NetworkFailure(
        'The download is ${format.label}.',
        suggestion: 'The server may have sent an error page instead of the '
            'JDK. Try again, or pick another vendor.',
      ),
    };

    final result = await _runner.run(
      command,
      arguments,
      timeout: const Duration(minutes: 10),
    );
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Could not unpack ${format.label} with `$command`. '
        'Make sure `$command` is installed and on PATH.',
        exitCode: result.exitCode,
        output: result.combinedOutput.trim(),
      );
    }
  }

  /// Puts the executable bit back on everything in the JDK that needs one.
  ///
  /// `tar` restores modes from the archive and Info-ZIP's `unzip` restores them
  /// from a zip's external attributes, so on a good day this changes nothing.
  /// It is not always a good day: a zip built on Windows carries no Unix modes
  /// at all, and a JDK whose `bin/java` is not executable fails at the first
  /// launch with a permission error that says nothing about why.
  ///
  /// `lib/jspawnhelper` is named explicitly because it is not under `bin` and
  /// the JVM cannot start a subprocess without it.
  Future<void> _restoreExecutableBits(String home) async {
    if (_platform.isWindows) return;

    final targets = executableTargets(home);
    if (targets.isEmpty) return;

    // No shell: a staging path with a space in it must not become two
    // arguments, and there is no glob here that needs expanding.
    final result = await _runner.run(
      'chmod',
      ['+x', ...targets],
      runInShell: false,
      timeout: const Duration(seconds: 30),
    );
    if (!result.isSuccess) {
      // Not fatal on its own — the bits may already be right. _validate is
      // what decides whether the install works.
      _log.warning('chmod +x on $home failed: ${result.combinedOutput.trim()}');
    }
  }

  /// Runs the JDK once, and reports why it did not start.
  ///
  /// The only check that covers everything the steps above can get wrong —
  /// wrong container, wrong root folder, missing execute bit, a truncated
  /// archive that still unpacked. Returns null when the JDK runs.
  Future<String?> _validate(String home) async {
    final java = File(p.join(home, 'bin', _platform.executableName('java')));
    if (!java.existsSync()) {
      return 'The unpacked JDK has no ${p.basename(java.path)} in its bin '
          'folder.';
    }
    try {
      final result = await _runner.run(
        java.path,
        ['-version'],
        runInShell: false,
        timeout: const Duration(minutes: 2),
      );
      if (result.isSuccess) {
        // `java -version` writes to stderr; combinedOutput has both.
        _log.info(
          'Installed JDK reports: ${result.combinedOutput.trim().split('\n').first}',
        );
        return null;
      }
      return 'The unpacked JDK would not run: '
          '${result.combinedOutput.trim().split('\n').first}';
    } on Failure catch (e) {
      return 'The unpacked JDK would not run: ${e.message}';
    }
  }

  /// Everything under [home] that has to be executable for the JDK to run.
  ///
  /// Every file in `bin`, plus the two helpers that live outside it. Missing
  /// entries are simply absent from the list — an older JDK has no `jexec`, and
  /// a `bin` that is not there at all is the [findJdkHome] failure, not this
  /// one. Split out from the chmod so the selection can be tested without
  /// running a process.
  static List<String> executableTargets(String home) {
    final targets = <String>[];
    final bin = Directory(p.join(home, 'bin'));
    if (bin.existsSync()) {
      for (final entry in bin.listSync()) {
        if (entry is File) targets.add(entry.path);
      }
    }
    for (final helper in const ['jspawnhelper', 'jexec']) {
      final file = File(p.join(home, 'lib', helper));
      if (file.existsSync()) targets.add(file.path);
    }
    return targets;
  }

  /// Why [actual] bytes is not the download the API promised, or null when it
  /// is (or when the API promised nothing).
  ///
  /// Pure, so the sizes that matter can be tested without a 200 MB file.
  static String? checkDownloadedSize({
    required int actual,
    required int? expected,
  }) {
    if (actual <= 0) return 'The download was empty. Try again.';
    if (expected == null || expected <= 0) return null;
    if (actual == expected) return null;

    const mb = 1024 * 1024;
    String size(int bytes) => '${(bytes / mb).toStringAsFixed(1)} MB';
    return actual < expected
        ? 'The download stopped early — ${size(actual)} of ${size(expected)}. '
              'Check your connection, then try again.'
        : 'The download was larger than published (${size(actual)} vs '
              '${size(expected)}), so it was discarded. Try again.';
  }

  /// SHA-256 of [file], read in chunks so a 200 MB archive never lands in
  /// memory whole.
  static Future<String> sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// The JDK root inside an unpacked archive.
  ///
  /// Three layouts, one answer. Both vendors normally wrap everything in one
  /// top-level folder (`jdk-21.0.12+8/`), but neither promises to, and a macOS
  /// archive puts the JDK another two levels down inside a `.jdk` bundle
  /// (`<bundle>/Contents/Home`). This checks the extraction root, then one
  /// level down, then that level's `Contents/Home`.
  ///
  /// The test is `bin/java` (or `bin/java.exe`), not the presence of a `bin`
  /// folder: an archive can carry a `bin` that holds no runtime, and the path
  /// this returns is the one the app registers and later launches.
  static String? findJdkHome(String unpackedRoot) {
    bool isHome(String directory) =>
        File(p.join(directory, 'bin', 'java')).existsSync() ||
        File(p.join(directory, 'bin', 'java.exe')).existsSync();

    if (isHome(unpackedRoot)) return unpackedRoot;
    try {
      for (final child in Directory(unpackedRoot).listSync()) {
        if (child is! Directory) continue;
        if (isHome(child.path)) return child.path;
        final bundled = p.join(child.path, 'Contents', 'Home');
        if (isHome(bundled)) return bundled;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
