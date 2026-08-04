part of 'address_cubit.dart';

enum AddressStatus { initial, loading, ready, failure }

class AddressState extends Equatable {
  const AddressState({
    this.status = AddressStatus.initial,
    this.addresses = const [],
    this.errorMessage,
  });

  final AddressStatus status;
  final List<Address> addresses;
  final String? errorMessage;

  bool get isLoading => status == AddressStatus.loading;

  AddressState copyWith({
    AddressStatus? status,
    List<Address>? addresses,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AddressState(
      status: status ?? this.status,
      addresses: addresses ?? this.addresses,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, addresses, errorMessage];
}
