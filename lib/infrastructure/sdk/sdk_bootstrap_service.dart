import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/failures.dart';
import '../../core/platform/platform_service.dart';
import '../archive/archive_extractor.dart';

/// Which part of the bootstrap is running, for the progress line.
enum SdkBootstrapStage {
  /// Fetching Google's command-line tools zip.
  downloading,

  /// Unpacking it and moving it into the layout sdkmanager requires.
  installing,

  /// Waiting for the user to accept the Android SDK licences.
  ///
  /// A deliberate stop, not a step that runs: the licences are Google's terms
  /// for the packages about to be downloaded, and clicking through them on the
  /// user's behalf without showing them is not this app's call to make.
  awaitingLicences,

  /// Running sdkmanager for the baseline packages.
  installingPackages,
  done,
  failed;

  String get label => switch (this) {
    SdkBootstrapStage.downloading => 'Downloading command-line tools…',
    SdkBootstrapStage.installing => 'Installing command-line tools…',
    SdkBootstrapStage.awaitingLicences => 'Licences need accepting',
    SdkBootstrapStage.installingPackages => 'Installing platform-tools…',
    SdkBootstrapStage.done => 'Ready',
    SdkBootstrapStage.failed => 'Failed',
  };
}

/// One step of the bootstrap, as it happens.
class SdkBootstrapEvent {
  const SdkBootstrapEvent({
    required this.stage,
    this.progress,
    this.sdkRoot,
    this.error,
  });

  final SdkBootstrapStage stage;

  /// 0–1 while downloading, null when the server sent no length.
  final double? progress;

  /// The SDK root, once the tools are in place — from
  /// [SdkBootstrapStage.awaitingLicences] onward.
  final String? sdkRoot;

  final String? error;
}

/// Creates an Android SDK from nothing.
///
/// The bootstrap problem this exists to solve: `cmdline-tools` is the package
/// that contains `sdkmanager`, and `sdkmanager` is the only thing that installs
/// packages. On a machine with no SDK the SDK manager page could only report
/// that it had nothing to work with — the one thing it could not do was fix it.
///
/// So this step alone does not use sdkmanager: it downloads Google's
/// command-line tools zip directly and lays it out by hand. Everything after it
/// goes through the normal `SdkRepository` path, because by then there is an
/// sdkmanager to go through.
@lazySingleton
class SdkBootstrapService {
  SdkBootstrapService(this._platform, this._extractor);

  final PlatformService _platform;
  final ArchiveExtractor _extractor;

  static final Logger _log = Logger('SdkBootstrapService');

  /// The build to fall back on when the repository manifest cannot be read.
  ///
  /// To bump it: open <https://developer.android.com/studio#command-line-tools-only>
  /// and take the number out of the `commandlinetools-linux-<build>_latest.zip`
  /// link. It is the same build number for all three platforms. This is only the
  /// fallback — [_resolveBuild] normally reads the current one from Google's own
  /// manifest, so a stale constant here costs nothing until Google takes the
  /// manifest away.
  static const String fallbackBuild = '13114758';

  /// Google's SDK repository index, which lists every command-line tools
  /// archive it publishes.
  static const String _manifestUrl =
      'https://dl.google.com/android/repository/repository2-3.xml';

  static const String _downloadBase =
      'https://dl.google.com/android/repository';

  static const _timeout = Duration(minutes: 15);

  CancelToken? _cancel;

  /// Where a Flutra-managed SDK lives: `<app support>/android-sdk`.
  ///
  /// The same convention as the managed JDKs — a folder this app owns, so no
  /// elevation is needed and uninstalling is deleting a directory.
  Future<Directory> managedRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'android-sdk'));
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  /// The archive name for this platform, e.g.
  /// `commandlinetools-linux-13114758_latest.zip`.
  ///
  /// Google's own naming, which uses `win`/`mac`/`linux` rather than the OS
  /// strings the rest of the app uses — hence [PlatformService.cmdlineToolsArchivePrefix].
  String archiveName(String build) =>
      '${_platform.cmdlineToolsArchivePrefix}-${build}_latest.zip';

  /// Downloads the command-line tools and lays them out so sdkmanager works.
  ///
  /// [intoSdkRoot] adds them to an SDK that already exists but has none — the
  /// half-installed case, where creating a second SDK beside the first would
  /// leave the machine with two and the user with a choice they did not ask
  /// for. Null creates the app-managed SDK.
  ///
  /// Stops at [SdkBootstrapStage.awaitingLicences] with the resolved [sdkRoot]
  /// attached. Installing the baseline packages is the caller's next step, so
  /// that the licences can be shown in between.
  Stream<SdkBootstrapEvent> installCommandLineTools({
    String? intoSdkRoot,
  }) async* {
    final cancel = CancelToken();
    _cancel = cancel;

    Directory? staging;
    try {
      final root = intoSdkRoot == null
          ? await managedRoot()
          : Directory(intoSdkRoot);
      staging = Directory(p.join(root.path, '.bootstrap'));
      // A run killed halfway leaves this behind; clearing it is what makes a
      // second attempt a fresh download rather than a retry on a partial file.
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      staging.createSync(recursive: true);

      yield const SdkBootstrapEvent(
        stage: SdkBootstrapStage.downloading,
        progress: 0,
      );

      final build = await _resolveBuild();
      final name = archiveName(build);
      final url = '$_downloadBase/$name';
      _log.info('Bootstrapping the Android SDK from $url into ${root.path}');

      final archive = File(p.join(staging.path, name));
      yield* _download(url, archive, cancel);

      if (!archive.existsSync() || archive.lengthSync() <= 0) {
        yield const SdkBootstrapEvent(
          stage: SdkBootstrapStage.failed,
          error: 'The download was empty. Check your connection and try again.',
        );
        return;
      }

      yield const SdkBootstrapEvent(stage: SdkBootstrapStage.installing);
      final unpacked = Directory(p.join(staging.path, 'unpacked'))
        ..createSync(recursive: true);
      await _extractor.extract(archive, unpacked);

      final tools = findToolsDir(unpacked.path);
      if (tools == null) {
        yield const SdkBootstrapEvent(
          stage: SdkBootstrapStage.failed,
          error: 'The downloaded archive did not contain the command-line '
              'tools (no bin/sdkmanager inside).',
        );
        return;
      }

      final destination = await _placeTools(root.path, tools);
      await _extractor.restoreExecutableBits(destination);

      final manager = File(
        p.join(destination, 'bin', _platform.scriptName('sdkmanager')),
      );
      if (!manager.existsSync()) {
        yield SdkBootstrapEvent(
          stage: SdkBootstrapStage.failed,
          error: 'sdkmanager is not where it should be after unpacking '
              '(${manager.path}).',
        );
        return;
      }

      yield SdkBootstrapEvent(
        stage: SdkBootstrapStage.awaitingLicences,
        sdkRoot: root.path,
      );
    } on Failure catch (e) {
      yield SdkBootstrapEvent(stage: SdkBootstrapStage.failed, error: e.message);
    } on FileSystemException catch (e) {
      yield SdkBootstrapEvent(
        stage: SdkBootstrapStage.failed,
        error: 'Could not write to disk: ${e.osError?.message ?? e.message}. '
            'Check the free space and permissions on the app data folder.',
      );
    } catch (e) {
      yield SdkBootstrapEvent(
        stage: SdkBootstrapStage.failed,
        error: cancel.isCancelled ? 'Cancelled.' : '$e',
      );
    } finally {
      _cancel = null;
      try {
        if (staging != null && staging.existsSync()) {
          staging.deleteSync(recursive: true);
        }
      } catch (e) {
        _log.fine('could not clear the bootstrap staging folder: $e');
      }
    }
  }

  /// Stops a bootstrap in flight. The partial download goes with the staging
  /// folder.
  void cancel() => _cancel?.cancel('cancelled by the user');

  bool get isRunning => _cancel != null;

  // ---- pieces --------------------------------------------------------------

  /// Moves the unpacked tools to `<root>/cmdline-tools/latest`.
  ///
  /// Google's zip unpacks to a bare `cmdline-tools/` with `bin` and `lib`
  /// directly inside it, and sdkmanager refuses to run from there: it resolves
  /// the SDK root by walking two directories up from its own `bin`, so it has to
  /// sit at `<root>/cmdline-tools/<channel>/bin`. Unpacked as-is it would look
  /// for the SDK one level too high and install packages into the wrong place —
  /// which is why this move is explicit rather than an extract straight into the
  /// destination.
  Future<String> _placeTools(String root, String unpackedTools) async {
    final channel = Directory(p.join(root, 'cmdline-tools', 'latest'));
    if (channel.existsSync()) channel.deleteSync(recursive: true);
    channel.parent.createSync(recursive: true);

    try {
      await Directory(unpackedTools).rename(channel.path);
    } on FileSystemException {
      // A rename across devices fails; the app-support folder and the temp dir
      // can genuinely be on different mounts on Linux.
      await _copyDirectory(Directory(unpackedTools), channel);
    }
    return channel.path;
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    to.createSync(recursive: true);
    for (final entry in from.listSync(recursive: true)) {
      final relative = p.relative(entry.path, from: from.path);
      final target = p.join(to.path, relative);
      if (entry is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entry is File) {
        Directory(p.dirname(target)).createSync(recursive: true);
        await entry.copy(target);
      }
    }
  }

  /// The current command-line tools build, from Google's manifest.
  ///
  /// Read rather than pinned so the app does not hand out a year-old sdkmanager
  /// to every new install. The manifest is XML, but nothing here needs a parser:
  /// the archive names are unique enough to match on directly, and pulling in an
  /// XML dependency to read one file name would be the larger cost. Falls back
  /// to [fallbackBuild] when the manifest cannot be read at all — an offline
  /// machine cannot download the zip either, but a manifest Google reorganises
  /// must not be what breaks the bootstrap.
  Future<String> _resolveBuild() async {
    try {
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.plain,
        ),
      ).get<dynamic>(_manifestUrl);
      final build = parseCmdlineToolsBuild(
        '${response.data}',
        _platform.cmdlineToolsArchivePrefix,
      );
      if (build != null) {
        _log.info('Command-line tools build $build, from the manifest.');
        return build;
      }
      _log.warning(
        'No ${_platform.cmdlineToolsArchivePrefix} archive in the manifest; '
        'using the pinned build $fallbackBuild.',
      );
    } catch (e) {
      _log.warning('Could not read the SDK manifest ($e); using $fallbackBuild.');
    }
    return fallbackBuild;
  }

  Stream<SdkBootstrapEvent> _download(
    String url,
    File target,
    CancelToken cancel,
  ) async* {
    final controller = StreamController<SdkBootstrapEvent>();
    final dio = Dio(BaseOptions(receiveTimeout: _timeout));

    final done = dio
        .download(
          url,
          target.path,
          cancelToken: cancel,
          onReceiveProgress: (received, total) {
            if (controller.isClosed) return;
            controller.add(
              SdkBootstrapEvent(
                stage: SdkBootstrapStage.downloading,
                progress: total > 0 ? received / total : null,
              ),
            );
          },
        )
        .whenComplete(controller.close);

    yield* controller.stream;
    await done;
  }

  /// The directory holding `bin/sdkmanager` inside an unpacked archive.
  ///
  /// Google wraps everything in `cmdline-tools/`, but this looks at the
  /// extraction root first and then one level down rather than trusting that —
  /// the same shape of check the JDK installer needs, and for the same reason.
  static String? findToolsDir(String unpackedRoot) {
    bool isTools(String directory) =>
        File(p.join(directory, 'bin', 'sdkmanager')).existsSync() ||
        File(p.join(directory, 'bin', 'sdkmanager.bat')).existsSync();

    if (isTools(unpackedRoot)) return unpackedRoot;
    try {
      for (final child in Directory(unpackedRoot).listSync()) {
        if (child is Directory && isTools(child.path)) return child.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

/// The newest command-line tools build for [prefix] in Google's manifest.
///
/// [prefix] is a [PlatformService.cmdlineToolsArchivePrefix] —
/// `commandlinetools-linux` and friends. The manifest lists several builds; the
/// highest number is the current one, and comparing them numerically rather than
/// as strings is what keeps a 9-digit build from sorting below an 8-digit one.
///
/// Pure, so the matching can be tested against a manifest excerpt.
String? parseCmdlineToolsBuild(String manifest, String prefix) {
  final pattern = RegExp('${RegExp.escape(prefix)}-(\\d+)_latest\\.zip');
  var best = 0;
  for (final match in pattern.allMatches(manifest)) {
    final build = int.tryParse(match.group(1)!) ?? 0;
    if (build > best) best = build;
  }
  return best == 0 ? null : '$best';
}
