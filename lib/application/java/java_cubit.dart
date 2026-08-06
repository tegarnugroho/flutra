import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/error/failures.dart';
import '../../core/platform/system_actions.dart';
import '../../domain/entities/jdk.dart';
import '../../domain/entities/jdk_compatibility.dart';
import '../../domain/entities/jdk_release.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../../infrastructure/java/jdk_catalog_service.dart';
import '../../infrastructure/java/jdk_detection_service.dart';
import '../../infrastructure/java/jdk_install_service.dart';
import '../../infrastructure/system/external_link_service.dart';
import '../settings/settings_cubit.dart';

part 'java_state.dart';

/// Drives the Java screen: find the JDKs, work out which one is in force, and
/// change that.
@injectable
class JavaCubit extends Cubit<JavaState> {
  JavaCubit(
    this._detection,
    this._catalog,
    this._installs,
    this._flutter,
    this._actions,
    this._links,
    this._settings,
  ) : super(const JavaState());

  final JdkDetectionService _detection;
  final JdkCatalogService _catalog;
  final JdkInstallService _installs;
  final FlutterRepository _flutter;
  final SystemActions _actions;
  final ExternalLinkService _links;
  final SettingsCubit _settings;

  /// Scans for JDKs and resolves the active one.
  ///
  /// [force] discards the detection cache — what Refresh does, and what has to
  /// happen after a JDK is installed or removed outside the app.
  Future<void> load({bool force = false}) async {
    if (isClosed) return;
    emit(state.copyWith(status: JavaStatus.loading, clearError: true));
    try {
      if (force) _detection.refresh();
      final jdks = await _detection.detect(
        manualPaths: _settings.state.manualJdkPaths,
        force: force,
      );
      if (isClosed) return;
      final pathJdk = await _detection.pathJdkHome();
      if (isClosed) return;

      // The list lands first. What follows shells out to Flutter, which takes
      // seconds on a cold tool cache, and none of it changes which JDKs exist.
      emit(state.copyWith(
        status: JavaStatus.ready,
        jdks: jdks,
        javaHome: _detection.javaHome,
        pathJdk: pathJdk,
      ));
      await _readFlutter();
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    }
  }

  /// What Flutter itself says: which JDK it was told to use, and which version
  /// it is — the second only feeds the Gradle compatibility hint.
  ///
  /// Failures here are silent by design: no Flutter on PATH is a fine state for
  /// this screen, which is about JDKs.
  Future<void> _readFlutter() async {
    final configured = await _flutter.configuredJdkDir();
    if (isClosed) return;
    emit(state.copyWith(
      flutterJdkDir: configured,
      clearFlutterJdkDir: configured == null,
    ));
    try {
      final info = await _flutter.getSdkInfo();
      if (!isClosed) emit(state.copyWith(flutterVersion: info.version));
    } on Failure {
      // No Flutter to ask; the hint simply stays quiet.
    }
  }

  /// Points `flutter config --jdk-dir` at [jdk] and re-resolves, without a
  /// rescan — the set of JDKs did not change, only which one is in force.
  Future<void> useForFlutter(Jdk jdk) async {
    await _run(jdk.path, JdkTask.settingFlutter, () async {
      await _flutter.setJdkDir(jdk.path);
      final configured = await _flutter.configuredJdkDir();
      if (isClosed) return;
      emit(state.copyWith(
        flutterJdkDir: configured,
        clearFlutterJdkDir: configured == null,
      ));
    });
  }

  /// Writes `JAVA_HOME` at user level.
  ///
  /// Never machine level: this app is not elevated, and rewriting a
  /// system-wide variable for every account on the box is not what "set my
  /// JDK" means. Returns the note to show, or null when it failed.
  Future<String?> setJavaHome(Jdk jdk) async {
    String? note;
    await _run(jdk.path, JdkTask.settingJavaHome, () async {
      final result = await _actions.persistUserEnvVar('JAVA_HOME', jdk.path);
      if (!result.success) {
        throw ProcessFailure(
          result.note ?? 'Could not write JAVA_HOME.',
          exitCode: -1,
          suggestion: 'Set it by hand in the environment variables dialog.',
        );
      }
      note = result.note;
      // The process this app runs in keeps the old value, so the panel would
      // otherwise keep reporting the previous JAVA_HOME until a restart.
      if (!isClosed) emit(state.copyWith(javaHome: jdk.path));
    });
    return note;
  }

  /// Fetches the downloadable JDKs, on demand rather than with the page.
  ///
  /// Two network calls for a dialog nobody opened would be two calls wasted, so
  /// this runs when the picker does.
  Future<void> loadCatalog({bool force = false}) async {
    if (isClosed) return;
    if (!force && state.catalogStatus == CatalogStatus.ready) return;
    emit(state.copyWith(
      catalogStatus: CatalogStatus.loading,
      clearCatalogError: true,
    ));
    try {
      final releases = await _catalog.available(
        vendor: state.catalogSource,
        forceRefresh: force,
      );
      if (isClosed) return;
      emit(state.copyWith(
        catalog: releases,
        catalogStatus: CatalogStatus.ready,
        catalogVendor: _catalog.servedBy,
      ));
    } on Failure catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          catalogStatus: CatalogStatus.failure,
          catalogError: e.message,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          catalogStatus: CatalogStatus.failure,
          catalogError: '$e',
        ));
      }
    }
  }

  /// Switches which API the picker reads from, and reloads it.
  ///
  /// Null means "whichever answers" — Adoptium, then Azul.
  Future<void> setCatalogSource(JdkVendor? vendor) async {
    if (isClosed || vendor == state.catalogSource) return;
    emit(state.copyWith(
      catalogSource: vendor,
      clearCatalogSource: vendor == null,
      catalog: const [],
      catalogStatus: CatalogStatus.initial,
    ));
    await loadCatalog();
  }

  /// Downloads, verifies and unpacks [release] into the app's own folder, then
  /// rescans so the new JDK appears in the list.
  Future<void> install(JdkRelease release) async {
    if (isClosed || state.installOf(release) != null) return;
    _install(release, const JdkInstallEvent(
      stage: JdkInstallStage.downloading,
      progress: 0,
    ));

    await for (final event in _installs.install(release)) {
      if (isClosed) return;
      _install(release, event);
      if (event.stage == JdkInstallStage.done) {
        // The install landed in the managed folder, which the scan reads.
        await load(force: true);
        if (isClosed) return;
        _install(release, null);
        return;
      }
      if (event.stage == JdkInstallStage.failed) return;
    }
  }

  /// Stops an install in flight; the partial download is discarded.
  void cancelInstall(JdkRelease release) {
    _installs.cancel(release);
    _install(release, null);
  }

  /// Clears a failed install's message once it has been read.
  void dismissInstall(JdkRelease release) => _install(release, null);

  /// Opens a build's archive in the browser, for anyone who would rather not
  /// have the app fetch 200 MB for them.
  Future<void> openDownload(JdkRelease release) =>
      _links.open(release.downloadUrl);

  void _install(JdkRelease release, JdkInstallEvent? event) {
    if (isClosed) return;
    final next = Map<String, JdkInstallEvent>.from(state.installs);
    if (event == null) {
      next.remove(release.downloadUrl);
    } else {
      next[release.downloadUrl] = event;
    }
    emit(state.copyWith(installs: next));
  }

  /// Validates [directory] as a JDK and remembers it.
  ///
  /// Returns null on success, or the reason it was rejected.
  Future<String?> addManualJdk(String directory) async {
    final jdk = await _detection.describe(directory, JdkSource.manual);
    if (jdk == null) {
      return 'Not a valid JDK (bin\\java.exe not found).';
    }
    final paths = [..._settings.state.manualJdkPaths];
    if (!paths.any((p) => samePath(p, jdk.path))) {
      paths.add(jdk.path);
      await _settings.setManualJdkPaths(paths);
    }
    await load();
    return null;
  }

  Future<void> _run(
    String path,
    JdkTask task,
    Future<void> Function() action,
  ) async {
    _task(path, task);
    try {
      await action();
    } on Failure catch (e) {
      _fail('${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}');
    } catch (e) {
      _fail('$e');
    } finally {
      _task(path, null);
    }
  }

  void _task(String path, JdkTask? task) {
    if (isClosed) return;
    final next = Map<String, JdkTask>.from(state.tasks);
    if (task == null) {
      next.remove(path);
    } else {
      next[path] = task;
    }
    emit(state.copyWith(tasks: next));
  }

  void _fail(String message) {
    if (isClosed) return;
    emit(state.copyWith(status: JavaStatus.failure, errorMessage: message));
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
