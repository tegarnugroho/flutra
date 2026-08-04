import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/doctor_report.dart';
import '../../infrastructure/doctor/doctor_runner.dart';
import '../../infrastructure/settings/settings_service.dart';

part 'flutter_doctor_state.dart';

/// Drives the Flutter doctor screen from the live `flutter doctor -v` stream.
@injectable
class FlutterDoctorCubit extends Cubit<FlutterDoctorState> {
  FlutterDoctorCubit(this._runner, this._settings)
      : super(const FlutterDoctorState());

  /// `flutter doctor` runs its validators concurrently, so several checks can
  /// resolve within the same few milliseconds. Revealing them one at a time
  /// keeps the list readable instead of flashing six rows at once.
  static const revealStagger = Duration(milliseconds: 120);

  static const _tick = Duration(milliseconds: 100);

  final DoctorRunner _runner;
  final SettingsService _settings;

  StreamSubscription<DoctorEvent>? _events;
  Timer? _stopwatch;
  Timer? _reveal;
  final List<DoctorEvent> _queued = [];
  Stopwatch? _clock;

  Future<void> run() async {
    if (isClosed || state.isRunning) return;
    _stop();

    final weights = _settings.settings.doctorTimings;
    // Reuse the last run's check order; fall back to the platform default.
    final expected =
        weights.isEmpty ? kDefaultDoctorChecks : weights.keys.toList();

    // Rows are replaced only now, not on the button press, so a re-run never
    // flashes an empty page.
    emit(FlutterDoctorState(
      status: DoctorRunStatus.running,
      checks: [for (final name in expected) DoctorCheck(name: name)],
      weights: weights,
    ));

    _clock = Stopwatch()..start();
    _stopwatch = Timer.periodic(_tick, (_) {
      if (isClosed || !state.isRunning) return;
      emit(state.copyWith(elapsed: _clock?.elapsed ?? Duration.zero));
    });

    _events = _runner.run(expectedChecks: expected).listen(_enqueue);
  }

  /// Kills the run; completed rows stay, the running row becomes an error.
  void cancel() => _runner.cancel();

  // ---- Event pipeline ------------------------------------------------------

  /// Events are queued so completions can be revealed [revealStagger] apart.
  void _enqueue(DoctorEvent event) {
    _queued.add(event);
    _drain();
  }

  void _drain() {
    if (_reveal != null || _queued.isEmpty || isClosed) return;
    final event = _queued.removeAt(0);
    _apply(event);
    // Only a resolution is worth pacing; everything else applies immediately.
    if (event is DoctorCheckResolved && _queued.isNotEmpty) {
      _reveal = Timer(revealStagger, () {
        _reveal = null;
        _drain();
      });
    } else if (_queued.isNotEmpty) {
      _drain();
    }
  }

  void _apply(DoctorEvent event) {
    if (isClosed) return;
    switch (event) {
      case DoctorRunStarted():
        break;

      case DoctorCheckStarted(:final name):
        _updateCheck(name, (c) => c.isDone
            ? c
            : c.copyWith(phase: DoctorCheckPhase.running));

      case DoctorCheckResolved():
        _resolve(event);

      case DoctorCheckDetails(:final name, :final lines):
        _updateCheck(name, (c) => c.copyWith(details: lines));

      case DoctorRunCompleted():
        _finish(event);

      case DoctorRunFailed(:final message, :final cancelled):
        _fail(message, cancelled: cancelled);
    }
  }

  void _resolve(DoctorCheckResolved event) {
    final checks = [...state.checks];
    final index = checks.indexWhere((c) => c.name == event.name);
    final resolved = DoctorCheck(
      name: event.name,
      phase: DoctorCheckPhase.done,
      status: event.status,
      title: event.title,
      summary: event.summary,
      elapsed: event.elapsed,
      details: index >= 0 ? checks[index].details : const [],
    );
    if (index >= 0) {
      checks[index] = resolved;
    } else {
      // A check this platform/version added that the expected list didn't
      // know about — append rather than drop it.
      checks.add(resolved);
    }
    emit(state.copyWith(checks: checks));
  }

  void _updateCheck(String name, DoctorCheck Function(DoctorCheck) update) {
    final checks = [...state.checks];
    final index = checks.indexWhere((c) => c.name == name);
    if (index < 0) return;
    checks[index] = update(checks[index]);
    emit(state.copyWith(checks: checks));
  }

  void _finish(DoctorRunCompleted event) {
    _stop();
    // Drop rows that never resolved: this run's check list is the truth.
    final checks = state.checks.where((c) => c.isDone).toList();
    emit(state.copyWith(
      status: DoctorRunStatus.done,
      checks: checks,
      elapsed: event.totalElapsed,
      rawOutput: event.rawOutput,
      clearError: true,
    ));
    unawaited(_persistTimings(checks));
  }

  void _fail(String message, {required bool cancelled}) {
    _stop();
    final hadRows = state.checks.any((c) => c.isDone);
    if (!hadRows) {
      emit(state.copyWith(
        status: DoctorRunStatus.failure,
        checks: const [],
        errorMessage: message,
      ));
      return;
    }
    // Keep what completed; the check that was mid-flight becomes an error row.
    final checks = [
      for (final c in state.checks)
        if (c.phase == DoctorCheckPhase.running)
          c.copyWith(
            phase: DoctorCheckPhase.done,
            status: DoctorStatus.error,
            title: c.name,
            summary: cancelled ? 'cancelled' : 'check interrupted',
          )
        else
          c,
    ];
    emit(state.copyWith(
      status: DoctorRunStatus.interrupted,
      checks: checks,
      errorMessage: message,
    ));
  }

  Future<void> _persistTimings(List<DoctorCheck> checks) async {
    final timings = <String, int>{
      for (final c in checks)
        if (c.elapsed != null) c.name: c.elapsed!.inMilliseconds,
    };
    if (timings.isEmpty) return;
    try {
      await _settings.save(
          _settings.settings.copyWith(doctorTimings: timings));
    } catch (_) {
      // Timings are an optimisation; losing them only affects the next bar.
    }
  }

  void _stop() {
    _stopwatch?.cancel();
    _stopwatch = null;
    _reveal?.cancel();
    _reveal = null;
    _queued.clear();
    _clock?.stop();
  }

  @override
  Future<void> close() {
    _stop();
    _events?.cancel();
    _runner.cancel();
    return super.close();
  }
}
