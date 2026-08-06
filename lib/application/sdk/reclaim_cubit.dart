import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_result.dart';
import '../../core/command/sdk_operation_lock.dart';
import '../../domain/entities/reclaimable_item.dart';
import '../../infrastructure/sdk/reclaim_executor.dart';
import '../../infrastructure/sdk/reclaim_scanner.dart';

part 'reclaim_state.dart';

/// Drives the reclaimable-storage dialog: scan, choose, remove.
///
/// Created per dialog rather than registered as a singleton — the report is
/// never persisted, because the only honest answer to "what can I delete" is
/// one that was measured just now.
@injectable
class ReclaimCubit extends Cubit<ReclaimState> {
  ReclaimCubit(this._scanner, this._executor, this._lock)
      : super(const ReclaimState());

  final ReclaimScanner _scanner;
  final ReclaimExecutor _executor;
  final SdkOperationLock _lock;

  StreamSubscription<(String, int)>? _sizes;
  StreamSubscription<ReclaimEvent>? _removal;

  /// Scans, then fills the sizes in as they are measured.
  Future<void> scan() async {
    if (isClosed) return;
    emit(const ReclaimState(phase: ReclaimPhase.scanning));
    try {
      final report = await _scanner.scan();
      if (isClosed) return;
      emit(state.copyWith(
        phase: ReclaimPhase.review,
        report: report,
        // Only the items nothing warns about start ticked. Anything with a
        // consequence is opt-in, however small it is.
        selected: {
          for (final item in report.items)
            if (item.isSafeDefault) item.id,
        },
      ));
      _measure(report.items);
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        phase: ReclaimPhase.review,
        errorMessage: 'Could not read the installed packages: $e',
      ));
    }
  }

  void _measure(List<ReclaimableItem> items) {
    _sizes?.cancel();
    _sizes = _scanner.measure(items).listen((measured) {
      if (isClosed) return;
      final report = state.report;
      if (report == null) return;
      final (id, bytes) = measured;
      emit(state.copyWith(
        report: ReclaimableReport(
          items: [
            for (final item in report.items)
              if (item.id == id) item.copyWith(sizeBytes: bytes) else item,
          ],
          scannedAt: report.scannedAt,
        ),
      ));
    });
  }

  void toggle(ReclaimableItem item) {
    if (isClosed || item.isBlocked || state.phase != ReclaimPhase.review) {
      return;
    }
    final selected = {...state.selected};
    if (!selected.remove(item.id)) selected.add(item.id);
    emit(state.copyWith(selected: selected));
  }

  /// Moves to the confirm step, which is the last point of no return.
  void review() {
    if (isClosed || state.selectedItems.isEmpty) return;
    emit(state.copyWith(phase: ReclaimPhase.confirm));
  }

  void back() {
    if (isClosed) return;
    emit(state.copyWith(phase: ReclaimPhase.review));
  }

  /// Removes the selection, one item at a time.
  Future<void> remove() async {
    if (isClosed || state.isRemoving) return;
    final items = state.selectedItems;
    if (items.isEmpty) return;

    if (_lock.isBusy) {
      emit(state.copyWith(
        errorMessage: '${_lock.busyLabel} is running on this SDK. Wait for it '
            'to finish, then try again.',
      ));
      return;
    }

    emit(state.copyWith(
      phase: ReclaimPhase.removing,
      clearError: true,
      lines: const [],
      statuses: {for (final item in items) item.id: ReclaimItemStatus.pending},
      freedBytes: 0,
    ));

    final done = Completer<void>();
    _removal = _executor.remove(items).listen(
      (event) {
        if (isClosed) return;
        switch (event) {
          case ReclaimLogged(:final text, :final isError):
            if (text.trim().isEmpty) return;
            emit(state.copyWith(
              lines: [...state.lines, CommandOutputLine(text, isError: isError)],
            ));
          case ReclaimItemStarted(:final itemId):
            emit(state.copyWith(
              currentItemId: itemId,
              statuses: {...state.statuses, itemId: ReclaimItemStatus.running},
            ));
          case ReclaimItemFinished(
              :final itemId,
              :final status,
              :final freedBytes,
              :final message,
            ):
            emit(state.copyWith(
              statuses: {...state.statuses, itemId: status},
              freedBytes: state.freedBytes + freedBytes,
              lines: message == null
                  ? state.lines
                  : [
                      ...state.lines,
                      CommandOutputLine(message,
                          isError: status == ReclaimItemStatus.failed),
                    ],
            ));
        }
      },
      onError: (Object e) {
        if (isClosed) return;
        emit(state.copyWith(
          lines: [...state.lines, CommandOutputLine('$e', isError: true)],
        ));
      },
      onDone: () {
        if (!isClosed) emit(state.copyWith(phase: ReclaimPhase.finished));
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: false,
    );
    await done.future;
  }

  /// Re-scans after a run, so the dialog reflects what is actually left.
  Future<void> rescan() => scan();

  @override
  Future<void> close() {
    _sizes?.cancel();
    _removal?.cancel();
    return super.close();
  }
}
