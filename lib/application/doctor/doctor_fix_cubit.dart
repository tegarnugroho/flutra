import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../core/command/command_result.dart';
import '../../domain/entities/doctor_issue.dart';
import '../../infrastructure/doctor/doctor_fix_service.dart';

part 'doctor_fix_state.dart';

/// Runs one doctor fix at a time and reports what it did.
///
/// Deliberately separate from [FlutterDoctorCubit]: a fix outlives the dialog
/// that started it, and the page needs to know a fix is running so it can
/// disable "Run again" and the other Fix buttons.
@injectable
class DoctorFixCubit extends Cubit<DoctorFixState> {
  DoctorFixCubit(this._service) : super(const DoctorFixState());

  final DoctorFixService _service;

  StreamSubscription<FixEvent>? _sub;

  /// The choices a guided fix offers, or an empty list for an automatic one.
  Future<List<FixChoice>> optionsFor(DoctorIssue issue) async {
    final executor = _service.executorFor(issue.id);
    if (executor == null) return const [];
    try {
      return await executor.options(_service.context());
    } catch (_) {
      // A scan that fails leaves the dialog on its manual "Browse…" path.
      return const [];
    }
  }

  /// The exact commands [issue] will run, for the confirm dialog.
  List<String> previewFor(DoctorIssue issue, {String? choice}) {
    final executor = _service.executorFor(issue.id);
    if (executor == null) return const [];
    return executor.preview(_service.context(choice: choice));
  }

  bool canFix(DoctorIssue issue) {
    final executor = _service.executorFor(issue.id);
    return executor != null && executor.isSupported;
  }

  /// Runs [issue]'s fix. [choice] is the guided selection, if it needed one.
  Future<void> run(DoctorIssue issue, {String? choice}) async {
    if (isClosed || state.isRunning) return;
    final executor = _service.executorFor(issue.id);
    if (executor == null) {
      emit(state.copyWith(
        phase: FixPhase.finished,
        issueId: issue.id,
        outcome: const FixOutcome.failed('This one has no automatic fix.'),
      ));
      return;
    }

    emit(DoctorFixState(
      phase: FixPhase.running,
      issueId: issue.id,
      issueTitle: issue.title,
    ));

    final done = Completer<void>();
    _sub = executor.execute(_service.context(choice: choice)).listen(
      (event) {
        if (isClosed) return;
        switch (event) {
          case FixLogged(:final text, :final isError):
            if (text.trim().isEmpty) return;
            emit(state.copyWith(
              lines: [...state.lines, CommandOutputLine(text, isError: isError)],
            ));
          case FixFinished(:final outcome):
            emit(state.copyWith(phase: FixPhase.finished, outcome: outcome));
        }
      },
      onError: (Object e) {
        if (isClosed) return;
        emit(state.copyWith(
          phase: FixPhase.finished,
          outcome: FixOutcome.failed('$e'),
          lines: [...state.lines, CommandOutputLine('$e', isError: true)],
        ));
      },
      onDone: () {
        // A stream that ends without a verdict means the fix was torn down
        // mid-flight; that is a failure, not a silent success.
        if (!isClosed && state.phase == FixPhase.running) {
          emit(state.copyWith(
            phase: FixPhase.finished,
            outcome: const FixOutcome.failed('The fix stopped unexpectedly.'),
          ));
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: false,
    );
    await done.future;
  }

  /// Runs every automatic fix in [issues], one after another.
  ///
  /// Stops at the first failure: these fixes are ordered by dependency in
  /// practice (licences before installs), and pressing on after one fails
  /// mostly produces a second, more confusing failure.
  Future<FixAllReport> runAll(List<DoctorIssue> issues) async {
    final auto = issues.where((i) => i.kind == FixKind.auto).toList();
    final deferred =
        issues.where((i) => i.kind != FixKind.auto).toList(growable: false);

    final fixed = <DoctorIssue>[];
    DoctorIssue? failedOn;
    var restartRequired = false;
    var blocksRerun = false;

    for (final issue in auto) {
      if (isClosed) break;
      await run(issue, choice: null);
      final outcome = state.outcome;
      if (outcome == null || !outcome.success) {
        failedOn = issue;
        break;
      }
      fixed.add(issue);
      restartRequired |= outcome.restartRequired;
      blocksRerun |= outcome.blocksRerun;
    }

    return FixAllReport(
      fixed: fixed,
      failedOn: failedOn,
      needsAttention: deferred,
      restartRequired: restartRequired,
      blocksRerun: blocksRerun,
    );
  }

  /// Clears the finished state so the page's buttons come back.
  void reset() {
    if (isClosed) return;
    _sub?.cancel();
    _sub = null;
    emit(const DoctorFixState());
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

/// What a "Fix all" pass managed, for the summary the page shows afterwards.
class FixAllReport {
  const FixAllReport({
    required this.fixed,
    required this.needsAttention,
    this.failedOn,
    this.restartRequired = false,
    this.blocksRerun = false,
  });

  final List<DoctorIssue> fixed;

  /// Guided and redirect issues, which "Fix all" never touches on its own.
  final List<DoctorIssue> needsAttention;

  final DoctorIssue? failedOn;
  final bool restartRequired;
  final bool blocksRerun;

  bool get anythingChanged => fixed.isNotEmpty;
}
