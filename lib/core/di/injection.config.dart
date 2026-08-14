// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutra/application/dashboard/dashboard_cubit.dart' as _i352;
import 'package:flutra/application/device/device_manager_cubit.dart' as _i4;
import 'package:flutra/application/doctor/doctor_fix_cubit.dart' as _i698;
import 'package:flutra/application/doctor/flutter_doctor_cubit.dart' as _i247;
import 'package:flutra/application/emulator/create_emulator_cubit.dart'
    as _i996;
import 'package:flutra/application/emulator/emulator_events.dart' as _i278;
import 'package:flutra/application/emulator/emulator_list_cubit.dart' as _i497;
import 'package:flutra/application/flutter_sdk/flutter_sdk_cubit.dart' as _i357;
import 'package:flutra/application/flutter_sdk/flutter_update_cubit.dart'
    as _i781;
import 'package:flutra/application/java/java_cubit.dart' as _i276;
import 'package:flutra/application/log/logcat_devices_cubit.dart' as _i194;
import 'package:flutra/application/sdk/reclaim_cubit.dart' as _i963;
import 'package:flutra/application/sdk/sdk_manager_cubit.dart' as _i276;
import 'package:flutra/application/settings/detected_paths_cubit.dart' as _i594;
import 'package:flutra/application/settings/settings_cubit.dart' as _i520;
import 'package:flutra/application/settings/theme_cubit.dart' as _i386;
import 'package:flutra/application/shell/shell_navigator.dart' as _i338;
import 'package:flutra/application/toolchain_events.dart' as _i774;
import 'package:flutra/application/windows/windows_cubit.dart' as _i745;
import 'package:flutra/core/command/command_runner.dart' as _i989;
import 'package:flutra/core/command/sdk_operation_lock.dart' as _i29;
import 'package:flutra/core/command/session_environment.dart' as _i282;
import 'package:flutra/core/platform/platform_service.dart' as _i427;
import 'package:flutra/core/platform/system_actions.dart' as _i964;
import 'package:flutra/domain/repositories/device_repository.dart' as _i804;
import 'package:flutra/domain/repositories/emulator_repository.dart' as _i932;
import 'package:flutra/domain/repositories/environment_repository.dart'
    as _i359;
import 'package:flutra/domain/repositories/flutter_repository.dart' as _i151;
import 'package:flutra/domain/repositories/sdk_repository.dart' as _i541;
import 'package:flutra/infrastructure/doctor/doctor_fix_service.dart' as _i327;
import 'package:flutra/infrastructure/doctor/doctor_runner.dart' as _i1018;
import 'package:flutra/infrastructure/flutter/flutter_releases_service.dart'
    as _i846;
import 'package:flutra/infrastructure/flutter/flutter_update_service.dart'
    as _i483;
import 'package:flutra/infrastructure/java/java_toolchain_service.dart'
    as _i901;
import 'package:flutra/infrastructure/java/jdk_catalog_service.dart' as _i712;
import 'package:flutra/infrastructure/java/jdk_detection_service.dart' as _i324;
import 'package:flutra/infrastructure/java/jdk_install_service.dart' as _i129;
import 'package:flutra/infrastructure/logging/dev_log_service.dart' as _i730;
import 'package:flutra/infrastructure/repositories/device_repository_impl.dart'
    as _i580;
import 'package:flutra/infrastructure/repositories/emulator_repository_impl.dart'
    as _i715;
import 'package:flutra/infrastructure/repositories/environment_repository_impl.dart'
    as _i241;
import 'package:flutra/infrastructure/repositories/flutter_repository_impl.dart'
    as _i17;
import 'package:flutra/infrastructure/repositories/sdk_repository_impl.dart'
    as _i871;
import 'package:flutra/infrastructure/sdk/flutter_locator.dart' as _i166;
import 'package:flutra/infrastructure/sdk/path_probe_service.dart' as _i936;
import 'package:flutra/infrastructure/sdk/reclaim_executor.dart' as _i990;
import 'package:flutra/infrastructure/sdk/reclaim_scanner.dart' as _i609;
import 'package:flutra/infrastructure/sdk/sdk_locator.dart' as _i706;
import 'package:flutra/infrastructure/sdk/sdk_scan_service.dart' as _i503;
import 'package:flutra/infrastructure/settings/legacy_data_migration.dart'
    as _i575;
import 'package:flutra/infrastructure/settings/settings_service.dart' as _i562;
import 'package:flutra/infrastructure/settings/startup_service.dart' as _i323;
import 'package:flutra/infrastructure/storage/storage_analysis_service.dart'
    as _i880;
import 'package:flutra/infrastructure/system/external_link_service.dart'
    as _i420;
import 'package:flutra/infrastructure/system/host_info_service.dart' as _i698;
import 'package:flutra/infrastructure/system/process_service.dart' as _i1039;
import 'package:flutra/infrastructure/trash/trash_service.dart' as _i509;
import 'package:flutra/infrastructure/windows/windows_toolchain_service.dart'
    as _i608;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final platformModule = _$PlatformModule();
    final systemActionsModule = _$SystemActionsModule();
    gh.singleton<_i278.EmulatorEvents>(
      () => _i278.EmulatorEvents(),
      dispose: (i) => i.dispose(),
    );
    gh.singleton<_i386.ThemeCubit>(() => _i386.ThemeCubit());
    gh.singleton<_i338.ShellNavigator>(
      () => _i338.ShellNavigator(),
      dispose: (i) => i.dispose(),
    );
    gh.singleton<_i774.ToolchainEvents>(
      () => _i774.ToolchainEvents(),
      dispose: (i) => i.dispose(),
    );
    gh.lazySingleton<_i29.SdkOperationLock>(() => _i29.SdkOperationLock());
    gh.lazySingleton<_i282.SessionEnvironment>(
      () => _i282.SessionEnvironment(),
    );
    gh.lazySingleton<_i427.PlatformService>(() => platformModule.platform);
    gh.lazySingleton<_i846.FlutterReleasesService>(
      () => _i846.FlutterReleasesService(),
    );
    gh.lazySingleton<_i730.DevLogService>(() => _i730.DevLogService());
    gh.lazySingleton<_i503.SdkScanService>(() => _i503.SdkScanService());
    gh.lazySingleton<_i562.SettingsService>(() => _i562.SettingsService());
    gh.lazySingleton<_i989.CommandRunner>(
      () => _i989.CommandRunner(gh<_i282.SessionEnvironment>()),
    );
    gh.lazySingleton<_i964.SystemActions>(
      () => systemActionsModule.actions(
        gh<_i989.CommandRunner>(),
        gh<_i427.PlatformService>(),
      ),
    );
    gh.lazySingleton<_i1018.DoctorRunner>(
      () => _i1018.DoctorRunner(
        gh<_i989.CommandRunner>(),
        gh<_i427.PlatformService>(),
      ),
    );
    gh.lazySingleton<_i936.PathProbeService>(
      () => _i936.PathProbeService(
        gh<_i989.CommandRunner>(),
        gh<_i427.PlatformService>(),
      ),
    );
    gh.lazySingleton<_i420.ExternalLinkService>(
      () => _i420.ExternalLinkService(
        gh<_i989.CommandRunner>(),
        gh<_i427.PlatformService>(),
      ),
    );
    gh.lazySingleton<_i712.JdkCatalogService>(
      () => _i712.JdkCatalogService(gh<_i427.PlatformService>()),
    );
    gh.lazySingleton<_i166.FlutterLocator>(
      () => _i166.FlutterLocator(gh<_i427.PlatformService>()),
    );
    gh.lazySingleton<_i706.SdkLocator>(
      () => _i706.SdkLocator(gh<_i427.PlatformService>()),
    );
    gh.lazySingleton<_i575.LegacyDataMigration>(
      () => _i575.LegacyDataMigration(gh<_i427.PlatformService>()),
    );
    gh.lazySingleton<_i932.EmulatorRepository>(
      () => _i715.EmulatorRepositoryImpl(
        gh<_i989.CommandRunner>(),
        gh<_i706.SdkLocator>(),
        gh<_i427.PlatformService>(),
      ),
    );
    gh.factory<_i497.EmulatorListCubit>(
      () => _i497.EmulatorListCubit(gh<_i932.EmulatorRepository>()),
    );
    gh.lazySingleton<_i129.JdkInstallService>(
      () => _i129.JdkInstallService(
        gh<_i712.JdkCatalogService>(),
        gh<_i989.CommandRunner>(),
        gh<_i427.PlatformService>(),
      ),
    );
    gh.factory<_i247.FlutterDoctorCubit>(
      () => _i247.FlutterDoctorCubit(
        gh<_i1018.DoctorRunner>(),
        gh<_i562.SettingsService>(),
      ),
    );
    gh.lazySingleton<_i804.DeviceRepository>(
      () => _i580.DeviceRepositoryImpl(
        gh<_i989.CommandRunner>(),
        gh<_i706.SdkLocator>(),
      ),
    );
    gh.lazySingleton<_i541.SdkRepository>(
      () => _i871.SdkRepositoryImpl(
        gh<_i989.CommandRunner>(),
        gh<_i706.SdkLocator>(),
        gh<_i29.SdkOperationLock>(),
      ),
    );
    gh.lazySingleton<_i880.StorageAnalysisService>(
      () => _i880.StorageAnalysisService(
        gh<_i706.SdkLocator>(),
        gh<_i166.FlutterLocator>(),
        gh<_i427.PlatformService>(),
      ),
    );
    gh.lazySingleton<_i323.StartupService>(
      () => _i323.StartupService(gh<_i989.CommandRunner>()),
    );
    gh.lazySingleton<_i698.HostInfoService>(
      () => _i698.HostInfoService(gh<_i989.CommandRunner>()),
    );
    gh.lazySingleton<_i1039.ProcessService>(
      () => _i1039.ProcessService(gh<_i989.CommandRunner>()),
    );
    gh.lazySingleton<_i509.TrashService>(
      () => _i509.TrashService(gh<_i989.CommandRunner>()),
    );
    gh.lazySingleton<_i609.ReclaimScanner>(
      () => _i609.ReclaimScanner(
        gh<_i541.SdkRepository>(),
        gh<_i706.SdkLocator>(),
        gh<_i427.PlatformService>(),
      ),
    );
    gh.lazySingleton<_i324.JdkDetectionService>(
      () => _i324.JdkDetectionService(
        gh<_i989.CommandRunner>(),
        gh<_i427.PlatformService>(),
        gh<_i129.JdkInstallService>(),
      ),
    );
    gh.factory<_i594.DetectedPathsCubit>(
      () => _i594.DetectedPathsCubit(
        gh<_i989.CommandRunner>(),
        gh<_i706.SdkLocator>(),
        gh<_i166.FlutterLocator>(),
        gh<_i503.SdkScanService>(),
      ),
    );
    gh.lazySingleton<_i151.FlutterRepository>(
      () => _i17.FlutterRepositoryImpl(
        gh<_i989.CommandRunner>(),
        gh<_i166.FlutterLocator>(),
        gh<_i509.TrashService>(),
        gh<_i427.PlatformService>(),
        gh<_i964.SystemActions>(),
        gh<_i420.ExternalLinkService>(),
      ),
    );
    gh.lazySingleton<_i990.ReclaimExecutor>(
      () => _i990.ReclaimExecutor(
        gh<_i541.SdkRepository>(),
        gh<_i509.TrashService>(),
        gh<_i964.SystemActions>(),
      ),
    );
    gh.lazySingleton<_i901.JavaToolchainService>(
      () => _i901.JavaToolchainService(
        gh<_i324.JdkDetectionService>(),
        gh<_i151.FlutterRepository>(),
        gh<_i562.SettingsService>(),
        gh<_i774.ToolchainEvents>(),
      ),
    );
    gh.lazySingleton<_i483.FlutterUpdateService>(
      () => _i483.FlutterUpdateService(
        gh<_i846.FlutterReleasesService>(),
        gh<_i151.FlutterRepository>(),
      ),
    );
    gh.factory<_i194.LogcatDevicesCubit>(
      () => _i194.LogcatDevicesCubit(gh<_i804.DeviceRepository>()),
    );
    gh.factory<_i781.FlutterUpdateCubit>(
      () => _i781.FlutterUpdateCubit(
        gh<_i151.FlutterRepository>(),
        gh<_i483.FlutterUpdateService>(),
      ),
    );
    gh.lazySingleton<_i608.WindowsToolchainService>(
      () => _i608.WindowsToolchainService(
        gh<_i989.CommandRunner>(),
        gh<_i427.PlatformService>(),
        gh<_i151.FlutterRepository>(),
      ),
    );
    gh.factory<_i276.SdkManagerCubit>(
      () => _i276.SdkManagerCubit(gh<_i541.SdkRepository>()),
    );
    gh.factory<_i357.FlutterSdkCubit>(
      () => _i357.FlutterSdkCubit(
        gh<_i151.FlutterRepository>(),
        gh<_i509.TrashService>(),
        gh<_i846.FlutterReleasesService>(),
      ),
    );
    gh.factory<_i996.CreateEmulatorCubit>(
      () => _i996.CreateEmulatorCubit(
        gh<_i932.EmulatorRepository>(),
        gh<_i541.SdkRepository>(),
        gh<_i698.HostInfoService>(),
      ),
    );
    gh.singleton<_i520.SettingsCubit>(
      () => _i520.SettingsCubit(
        gh<_i562.SettingsService>(),
        gh<_i323.StartupService>(),
        gh<_i706.SdkLocator>(),
        gh<_i166.FlutterLocator>(),
        gh<_i386.ThemeCubit>(),
      ),
    );
    gh.factory<_i963.ReclaimCubit>(
      () => _i963.ReclaimCubit(
        gh<_i609.ReclaimScanner>(),
        gh<_i990.ReclaimExecutor>(),
        gh<_i29.SdkOperationLock>(),
      ),
    );
    gh.factory<_i4.DeviceManagerCubit>(
      () => _i4.DeviceManagerCubit(
        gh<_i804.DeviceRepository>(),
        gh<_i151.FlutterRepository>(),
      ),
    );
    gh.lazySingleton<_i327.DoctorFixService>(
      () => _i327.DoctorFixService(
        gh<_i989.CommandRunner>(),
        gh<_i706.SdkLocator>(),
        gh<_i166.FlutterLocator>(),
        gh<_i503.SdkScanService>(),
        gh<_i282.SessionEnvironment>(),
        gh<_i541.SdkRepository>(),
        gh<_i151.FlutterRepository>(),
        gh<_i427.PlatformService>(),
        gh<_i964.SystemActions>(),
      ),
    );
    gh.lazySingleton<_i359.EnvironmentRepository>(
      () => _i241.EnvironmentRepositoryImpl(
        gh<_i989.CommandRunner>(),
        gh<_i706.SdkLocator>(),
        gh<_i483.FlutterUpdateService>(),
        gh<_i427.PlatformService>(),
        gh<_i901.JavaToolchainService>(),
      ),
    );
    gh.factory<_i745.WindowsCubit>(
      () => _i745.WindowsCubit(gh<_i608.WindowsToolchainService>()),
    );
    gh.factory<_i276.JavaCubit>(
      () => _i276.JavaCubit(
        gh<_i324.JdkDetectionService>(),
        gh<_i901.JavaToolchainService>(),
        gh<_i712.JdkCatalogService>(),
        gh<_i129.JdkInstallService>(),
        gh<_i151.FlutterRepository>(),
        gh<_i964.SystemActions>(),
        gh<_i420.ExternalLinkService>(),
        gh<_i520.SettingsCubit>(),
      ),
    );
    gh.factory<_i352.DashboardCubit>(
      () => _i352.DashboardCubit(
        gh<_i359.EnvironmentRepository>(),
        gh<_i932.EmulatorRepository>(),
        gh<_i804.DeviceRepository>(),
        gh<_i541.SdkRepository>(),
        gh<_i880.StorageAnalysisService>(),
        gh<_i774.ToolchainEvents>(),
      ),
    );
    gh.factory<_i698.DoctorFixCubit>(
      () => _i698.DoctorFixCubit(gh<_i327.DoctorFixService>()),
    );
    return this;
  }
}

class _$PlatformModule extends _i427.PlatformModule {}

class _$SystemActionsModule extends _i964.SystemActionsModule {}
