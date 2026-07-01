// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:android_sdk_manager/application/dashboard/dashboard_cubit.dart'
    as _i75;
import 'package:android_sdk_manager/application/settings/theme_cubit.dart'
    as _i245;
import 'package:android_sdk_manager/core/command/command_runner.dart' as _i144;
import 'package:android_sdk_manager/domain/repositories/environment_repository.dart'
    as _i595;
import 'package:android_sdk_manager/infrastructure/repositories/environment_repository_impl.dart'
    as _i465;
import 'package:android_sdk_manager/infrastructure/sdk/sdk_locator.dart'
    as _i839;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    gh.singleton<_i245.ThemeCubit>(() => _i245.ThemeCubit());
    gh.lazySingleton<_i144.CommandRunner>(() => _i144.CommandRunner());
    gh.lazySingleton<_i839.SdkLocator>(() => _i839.SdkLocator());
    gh.lazySingleton<_i595.EnvironmentRepository>(
      () => _i465.EnvironmentRepositoryImpl(
        gh<_i144.CommandRunner>(),
        gh<_i839.SdkLocator>(),
      ),
    );
    gh.factory<_i75.DashboardCubit>(
      () => _i75.DashboardCubit(gh<_i595.EnvironmentRepository>()),
    );
    return this;
  }
}
