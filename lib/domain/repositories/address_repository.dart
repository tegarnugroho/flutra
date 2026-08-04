import '../entities/address.dart';

/// Fetches user addresses from the settings API.
abstract class AddressRepository {
  /// GET `{baseUrl}/api/settings/addresses`. Throws a [Failure] on error.
  Future<List<Address>> getAddresses();
}
