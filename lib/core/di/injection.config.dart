// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:android_sdk_manager/application/address/address_cubit.dart'
    as _i510;
import 'package:android_sdk_manager/application/dashboard/dashboard_cubit.dart'
    as _i75;
import 'package:android_sdk_manager/application/device/device_manager_cubit.dart'
    as _i884;
import 'package:android_sdk_manager/application/doctor/doctor_fix_cubit.dart'
    as _i517;
import 'package:android_sdk_manager/application/doctor/flutter_doctor_cubit.dart'
    as _i915;
import 'package:android_sdk_manager/application/emulator/create_emulator_cubit.dart'
    as _i622;
import 'package:android_sdk_manager/application/emulator/emulator_events.dart'
    as _i1064;
import 'package:android_sdk_manager/application/emulator/emulator_list_cubit.dart'
    as _i6;
import 'package:android_sdk_manager/application/flutter_sdk/flutter_sdk_cubit.dart'
    as _i502;
import 'package:android_sdk_manager/application/flutter_sdk/flutter_update_cubit.dart'
    as _i839;
import 'package:android_sdk_manager/application/log/logcat_devices_cubit.dart'
    as _i643;
import 'package:android_sdk_manager/application/sdk/reclaim_cubit.dart' as _i26;
import 'package:android_sdk_manager/application/sdk/sdk_manager_cubit.dart'
    as _i740;
import 'package:android_sdk_manager/application/settings/detected_paths_cubit.dart'
    as _i775;
import 'package:android_sdk_manager/application/settings/settings_cubit.dart'
    as _i698;
import 'package:android_sdk_manager/application/settings/theme_cubit.dart'
    as _i245;
import 'package:android_sdk_manager/application/shell/shell_navigator.dart'
    as _i684;
import 'package:android_sdk_manager/core/command/command_runner.dart' as _i144;
import 'package:android_sdk_manager/core/command/sdk_operation_lock.dart'
    as _i328;
import 'package:android_sdk_manager/core/command/session_environment.dart'
    as _i771;
import 'package:android_sdk_manager/domain/repositories/address_repository.dart'
    as _i1013;
import 'package:android_sdk_manager/domain/repositories/device_repository.dart'
    as _i720;
import 'package:android_sdk_manager/domain/repositories/emulator_repository.dart'
    as _i277;
import 'package:android_sdk_manager/domain/repositories/environment_repository.dart'
    as _i595;
import 'package:android_sdk_manager/domain/repositories/flutter_repository.dart'
    as _i606;
import 'package:android_sdk_manager/domain/repositories/sdk_repository.dart'
    as _i374;
import 'package:android_sdk_manager/infrastructure/doctor/doctor_fix_service.dart'
    as _i57;
import 'package:android_sdk_manager/infrastructure/doctor/doctor_runner.dart'
    as _i706;
import 'package:android_sdk_manager/infrastructure/flutter/flutter_releases_service.dart'
    as _i961;
import 'package:android_sdk_manager/infrastructure/flutter/flutter_update_service.dart'
    as _i147;
import 'package:android_sdk_manager/infrastructure/logging/dev_log_service.dart'
    as _i848;
import 'package:android_sdk_manager/infrastructure/repositories/address_repository_impl.dart'
    as _i886;
import 'package:android_sdk_manager/infrastructure/repositories/device_repository_impl.dart'
    as _i775;
import 'package:android_sdk_manager/infrastructure/repositories/emulator_repository_impl.dart'
    as _i60;
import 'package:android_sdk_manager/infrastructure/repositories/environment_repository_impl.dart'
    as _i465;
import 'package:android_sdk_manager/infrastructure/repositories/flutter_repository_impl.dart'
    as _i483;
import 'package:android_sdk_manager/infrastructure/repositories/sdk_repository_impl.dart'
    as _i77;
import 'package:android_sdk_manager/infrastructure/sdk/flutter_locator.dart'
    as _i1034;
import 'package:android_sdk_manager/infrastructure/sdk/path_probe_service.dart'
    as _i220;
import 'package:android_sdk_manager/infrastructure/sdk/reclaim_executor.dart'
    as _i164;
import 'package:android_sdk_manager/infrastructure/sdk/reclaim_scanner.dart'
    as _i821;
import 'package:android_sdk_manager/infrastructure/sdk/sdk_locator.dart'
    as _i839;
import 'package:android_sdk_manager/infrastructure/sdk/sdk_scan_service.dart'
    as _i404;
import 'package:android_sdk_manager/infrastructure/settings/settings_service.dart'
    as _i517;
import 'package:android_sdk_manager/infrastructure/settings/startup_service.dart'
    as _i104;
import 'package:android_sdk_manager/infrastructure/storage/storage_analysis_service.dart'
    as _i927;
import 'package:android_sdk_manager/infrastructure/system/external_link_service.dart'
    as _i1017;
import 'package:android_sdk_manager/infrastructure/system/host_info_service.dart'
    as _i361;
import 'package:android_sdk_manager/infrastructure/system/process_service.dart'
    as _i891;
import 'package:android_sdk_manager/infrastructure/trash/trash_service.dart'
    as _i95;
import 'package:android_sdk_manager/presentation/window/warm_window_pool.dart'
    as _i188;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    gh.singleton<_i1064.EmulatorEvents>(
      () => _i1064.EmulatorEvents(),
      dispose: (i) => i.dispose(),
    );
    gh.singleton<_i245.ThemeCubit>(() => _i245.ThemeCubit());
    gh.singleton<_i684.ShellNavigator>(
      () => _i684.ShellNavigator(),
      dispose: (i) => i.dispose(),
    );
    gh.lazySingleton<_i328.SdkOperationLock>(() => _i328.SdkOperationLock());
    gh.lazySingleton<_i771.SessionEnvironment>(
      () => _i771.SessionEnvironment(),
    );
    gh.lazySingleton<_i961.FlutterReleasesService>(
      () => _i961.FlutterReleasesService(),
    );
    gh.lazySingleton<_i848.DevLogService>(() => _i848.DevLogService());
    gh.lazySingleton<_i1034.FlutterLocator>(() => _i1034.FlutterLocator());
    gh.lazySingleton<_i839.SdkLocator>(() => _i839.SdkLocator());
    gh.lazySingleton<_i404.SdkScanService>(() => _i404.SdkScanService());
    gh.lazySingleton<_i517.SettingsService>(() => _i517.SettingsService());
    gh.lazySingleton<_i188.WarmWindowPool>(
      () => _i188.WarmWindowPool(),
      dispose: (i) => i.dispose(),
    );
    gh.lazySingleton<_i144.CommandRunner>(
      () => _i144.CommandRunner(gh<_i771.SessionEnvironment>()),
    );
    gh.lazySingleton<_i277.EmulatorRepository>(
      () => _i60.EmulatorRepositoryImpl(
        gh<_i144.CommandRunner>(),
        gh<_i839.SdkLocator>(),
      ),
    );
    gh.lazySingleton<_i1013.AddressRepository>(
      () => _i886.AddressRepositoryImpl(gh<_i517.SettingsService>()),
    );
    gh.lazySingleton<_i720.DeviceRepository>(
      () => _i775.DeviceRepositoryImpl(
        gh<_i144.CommandRunner>(),
        gh<_i839.SdkLocator>(),
      ),
    );
    gh.lazySingleton<_i927.StorageAnalysisService>(
      () => _i927.StorageAnalysisService(
        gh<_i839.SdkLocator>(),
        gh<_i1034.FlutterLocator>(),
      ),
    );
    gh.factory<_i510.AddressCubit>(
      () => _i510.AddressCubit(gh<_i1013.AddressRepository>()),
    );
    gh.factory<_i643.LogcatDevicesCubit>(
      () => _i643.LogcatDevicesCubit(gh<_i720.DeviceRepository>()),
    );
    gh.factory<_i6.EmulatorListCubit>(
      () => _i6.EmulatorListCubit(gh<_i277.EmulatorRepository>()),
    );
    gh.factory<_i775.DetectedPathsCubit>(
      () => _i775.DetectedPathsCubit(
        gh<_i144.CommandRunner>(),
        gh<_i839.SdkLocator>(),
        gh<_i1034.FlutterLocator>(),
        gh<_i404.SdkScanService>(),
      ),
    );
    gh.lazySingleton<_i374.SdkRepository>(
      () => _i77.SdkRepositoryImpl(
        gh<_i144.CommandRunner>(),
        gh<_i839.SdkLocator>(),
        gh<_i328.SdkOperationLock>(),
      ),
    );
    gh.lazySingleton<_i706.DoctorRunner>(
      () => _i706.DoctorRunner(gh<_i144.CommandRunner>()),
    );
    gh.lazySingleton<_i220.PathProbeService>(
      () => _i220.PathProbeService(gh<_i144.CommandRunner>()),
    );
    gh.lazySingleton<_i104.StartupService>(
      () => _i104.StartupService(gh<_i144.CommandRunner>()),
    );
    gh.lazySingleton<_i1017.ExternalLinkService>(
      () => _i1017.ExternalLinkService(gh<_i144.CommandRunner>()),
    );
    gh.lazySingleton<_i361.HostInfoService>(
      () => _i361.HostInfoService(gh<_i144.CommandRunner>()),
    );
    gh.lazySingleton<_i891.ProcessService>(
      () => _i891.ProcessService(gh<_i144.CommandRunner>()),
    );
    gh.lazySingleton<_i95.TrashService>(
      () => _i95.TrashService(gh<_i144.CommandRunner>()),
    );
    gh.lazySingleton<_i164.ReclaimExecutor>(
      () => _i164.ReclaimExecutor(
        gh<_i374.SdkRepository>(),
        gh<_i95.TrashService>(),
      ),
    );
    gh.lazySingleton<_i606.FlutterRepository>(
      () => _i483.FlutterRepositoryImpl(
        gh<_i144.CommandRunner>(),
        gh<_i1034.FlutterLocator>(),
        gh<_i95.TrashService>(),
      ),
    );
    gh.factory<_i622.CreateEmulatorCubit>(
      () => _i622.CreateEmulatorCubit(
        gh<_i277.EmulatorRepository>(),
        gh<_i374.SdkRepository>(),
        gh<_i361.HostInfoService>(),
      ),
    );
    gh.lazySingleton<_i57.DoctorFixService>(
      () => _i57.DoctorFixService(
        gh<_i144.CommandRunner>(),
        gh<_i839.SdkLocator>(),
        gh<_i1034.FlutterLocator>(),
        gh<_i404.SdkScanService>(),
        gh<_i771.SessionEnvironment>(),
        gh<_i374.SdkRepository>(),
        gh<_i606.FlutterRepository>(),
      ),
    );
    gh.singleton<_i698.SettingsCubit>(
      () => _i698.SettingsCubit(
        gh<_i517.SettingsService>(),
        gh<_i104.StartupService>(),
        gh<_i839.SdkLocator>(),
        gh<_i1034.FlutterLocator>(),
        gh<_i245.ThemeCubit>(),
      ),
    );
    gh.factory<_i884.DeviceManagerCubit>(
      () => _i884.DeviceManagerCubit(
        gh<_i720.DeviceRepository>(),
        gh<_i606.FlutterRepository>(),
      ),
    );
    gh.lazySingleton<_i821.ReclaimScanner>(
      () => _i821.ReclaimScanner(
        gh<_i374.SdkRepository>(),
        gh<_i839.SdkLocator>(),
      ),
    );
    gh.factory<_i740.SdkManagerCubit>(
      () => _i740.SdkManagerCubit(gh<_i374.SdkRepository>()),
    );
    gh.factory<_i502.FlutterSdkCubit>(
      () => _i502.FlutterSdkCubit(
        gh<_i606.FlutterRepository>(),
        gh<_i95.TrashService>(),
        gh<_i961.FlutterReleasesService>(),
      ),
    );
    gh.lazySingleton<_i147.FlutterUpdateService>(
      () => _i147.FlutterUpdateService(
        gh<_i961.FlutterReleasesService>(),
        gh<_i606.FlutterRepository>(),
      ),
    );
    gh.factory<_i517.DoctorFixCubit>(
      () => _i517.DoctorFixCubit(gh<_i57.DoctorFixService>()),
    );
    gh.lazySingleton<_i595.EnvironmentRepository>(
      () => _i465.EnvironmentRepositoryImpl(
        gh<_i144.CommandRunner>(),
        gh<_i839.SdkLocator>(),
        gh<_i147.FlutterUpdateService>(),
      ),
    );
    gh.factory<_i26.ReclaimCubit>(
      () => _i26.ReclaimCubit(
        gh<_i821.ReclaimScanner>(),
        gh<_i164.ReclaimExecutor>(),
        gh<_i328.SdkOperationLock>(),
      ),
    );
    gh.factory<_i915.FlutterDoctorCubit>(
      () => _i915.FlutterDoctorCubit(
        gh<_i706.DoctorRunner>(),
        gh<_i517.SettingsService>(),
      ),
    );
    gh.factory<_i839.FlutterUpdateCubit>(
      () => _i839.FlutterUpdateCubit(
        gh<_i606.FlutterRepository>(),
        gh<_i147.FlutterUpdateService>(),
      ),
    );
    gh.factory<_i75.DashboardCubit>(
      () => _i75.DashboardCubit(
        gh<_i595.EnvironmentRepository>(),
        gh<_i277.EmulatorRepository>(),
        gh<_i720.DeviceRepository>(),
        gh<_i374.SdkRepository>(),
        gh<_i927.StorageAnalysisService>(),
      ),
    );
    return this;
  }
}
