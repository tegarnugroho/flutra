import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/flutter_update_status.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../../infrastructure/flutter/flutter_update_service.dart';

part 'flutter_update_state.dart';

/// Checks whether the installed Flutter SDK is behind its channel tip.
///
/// Lives on its own so any screen can show the state without dragging in the
/// whole Flutter SDK screen's cubit.
@injectable
class FlutterUpdateCubit extends Cubit<FlutterUpdateState> {
  FlutterUpdateCubit(this._repository, this._updates)
      : super(const FlutterUpdateState());

  final FlutterRepository _repository;
  final FlutterUpdateService _updates;

  /// [forceRefresh] re-downloads the release index instead of using the cache.
  Future<void> check({bool forceRefresh = false}) async {
    if (isClosed) return;
    // Keep the previous result visible while re-checking.
    emit(FlutterUpdateState(
        status: FlutterUpdateCheckStatus.loading, update: state.update));
    try {
      final info = await _repository.getSdkInfo();
      final update =
          await _updates.check(channel: info.channel, forceRefresh: forceRefresh);
      if (isClosed) return;
      emit(update == null
          ? const FlutterUpdateState(
              status: FlutterUpdateCheckStatus.unavailable)
          : FlutterUpdateState(
              status: FlutterUpdateCheckStatus.ready, update: update));
    } catch (_) {
      // No SDK installed, or it can't be read — neither is an error worth
      // shouting about on a page that is mostly about Android packages.
      if (!isClosed) {
        emit(const FlutterUpdateState(
            status: FlutterUpdateCheckStatus.unavailable));
      }
    }
  }
}
