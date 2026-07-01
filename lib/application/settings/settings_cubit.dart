import 'package:bloc/bloc.dart';
import 'package:fluent_ui/fluent_ui.dart' show ThemeMode;
import 'package:injectable/injectable.dart';

import '../../infrastructure/sdk/flutter_locator.dart';
import '../../infrastructure/sdk/sdk_locator.dart';
import '../../infrastructure/settings/settings_service.dart';
import '../../infrastructure/settings/startup_service.dart';
import 'app_settings.dart';
import 'theme_cubit.dart';

/// Drives the Settings screen and applies preferences app-wide (theme via
/// [ThemeCubit], SDK overrides via [SdkLocator]/[FlutterLocator], startup via
/// [StartupService]).
@singleton
class SettingsCubit extends Cubit<AppSettings> {
  SettingsCubit(
    this._service,
    this._startup,
    this._locator,
    this._flutterLocator,
    this._theme,
  ) : super(_service.settings);

  final SettingsService _service;
  final StartupService _startup;
  final SdkLocator _locator;
  final FlutterLocator _flutterLocator;
  final ThemeCubit _theme;

  /// Loads persisted settings and reconciles the run-at-startup flag with the
  /// actual registry state.
  Future<void> init() async {
    var settings = await _service.load();
    final actualStartup = await _startup.isEnabled();
    if (actualStartup != settings.runAtStartup) {
      settings = settings.copyWith(runAtStartup: actualStartup);
      await _service.save(settings);
    }
    _apply(settings);
    if (!isClosed) emit(settings);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _theme.setMode(mode);
    await _persist(state.copyWith(themeMode: mode));
  }

  Future<void> setAndroidSdkPath(String path) async {
    final trimmed = path.trim();
    _locator.overrideSdkRoot = trimmed.isEmpty ? null : trimmed;
    await _persist(state.copyWith(
      androidSdkPath: trimmed.isEmpty ? null : trimmed,
      clearAndroidSdkPath: trimmed.isEmpty,
    ));
  }

  Future<void> setFlutterSdkPath(String path) async {
    final trimmed = path.trim();
    _flutterLocator.overrideFlutterRoot = trimmed.isEmpty ? null : trimmed;
    await _persist(state.copyWith(
      flutterSdkPath: trimmed.isEmpty ? null : trimmed,
      clearFlutterSdkPath: trimmed.isEmpty,
    ));
  }

  Future<void> setRunAtStartup(bool value) async {
    await _startup.setEnabled(value);
    await _persist(state.copyWith(runAtStartup: value));
  }

  Future<void> setCloseToTray(bool value) =>
      _persist(state.copyWith(closeToTray: value));

  Future<void> setDeveloperMode(bool value) =>
      _persist(state.copyWith(developerMode: value));

  void _apply(AppSettings s) {
    _theme.setMode(s.themeMode);
    _locator.overrideSdkRoot = s.androidSdkPath;
    _flutterLocator.overrideFlutterRoot = s.flutterSdkPath;
  }

  Future<void> _persist(AppSettings settings) async {
    await _service.save(settings);
    if (!isClosed) emit(settings);
  }
}
