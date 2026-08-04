import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/error/failures.dart';
import '../../domain/entities/address.dart';
import '../../domain/repositories/address_repository.dart';

part 'address_state.dart';

/// Loads user addresses from the settings API.
@injectable
class AddressCubit extends Cubit<AddressState> {
  AddressCubit(this._repository) : super(const AddressState());

  final AddressRepository _repository;

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(status: AddressStatus.loading, clearError: true));
    try {
      final addresses = await _repository.getAddresses();
      if (isClosed) return;
      emit(state.copyWith(status: AddressStatus.ready, addresses: addresses));
    } on Failure catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        status: AddressStatus.failure,
        errorMessage:
            '${e.message}${e.suggestion == null ? '' : '\n${e.suggestion}'}',
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: AddressStatus.failure, errorMessage: '$e'));
    }
  }
}
