import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../core/error/failures.dart';
import '../../domain/entities/address.dart';
import '../../domain/repositories/address_repository.dart';
import '../settings/settings_service.dart';

/// [AddressRepository] backed by the settings HTTP API.
@LazySingleton(as: AddressRepository)
class AddressRepositoryImpl implements AddressRepository {
  AddressRepositoryImpl(this._settings);

  final SettingsService _settings;

  @override
  Future<List<Address>> getAddresses() async {
    final base = _settings.settings.apiBaseUrl;
    if (base == null || base.isEmpty) {
      throw const NetworkFailure(
        'No API base URL configured.',
        suggestion: 'Set the API base URL in Settings first.',
      );
    }
    try {
      final response = await Dio().get<dynamic>(
        '$base/api/settings/addresses',
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['data'] as List?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(Address.fromJson)
          .toList();
    } on DioException catch (e) {
      throw NetworkFailure(
        'Failed to load addresses (${e.response?.statusCode ?? 'no response'}).',
        suggestion: 'Check the base URL and your connection.',
        cause: e,
      );
    } catch (e) {
      throw NetworkFailure('Failed to load addresses.', cause: e);
    }
  }
}
