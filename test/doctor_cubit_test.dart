import 'dart:async';

import 'package:android_sdk_manager/application/doctor/flutter_doctor_cubit.dart';
import 'package:android_sdk_manager/application/settings/app_settings.dart';
import 'package:android_sdk_manager/core/command/command_runner.dart';
import 'package:android_sdk_manager/domain/entities/doctor_report.dart';
import 'package:android_sdk_manager/infrastructure/doctor/doctor_runner.dart';
import 'package:android_sdk_manager/core/command/session_environment.dart';
import 'package:android_sdk_manager/core/platform/platform_service.dart';
import 'package:android_sdk_manager/infrastructure/settings/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A runner the test drives by hand, so event ordering is deterministic.
class _FakeRunner extends DoctorRunner {
  _FakeRunner()
      : super(CommandRunner(SessionEnvironment()), hostPlatform);

  final _controller = StreamController<DoctorEvent>();
  List<String>? requestedChecks;
  var cancelled = false;

  @override
  Stream<DoctorEvent> run({List<String> expectedChecks = kDefaultDoctorChecks}) {
    requestedChecks = expectedChecks;
    return _controller.stream;
  }

  @override
  void cancel() => cancelled = true;

  void emit(DoctorEvent event) => _controller.add(event);

  Future<void> close() => _controller.close();
}

/// Keeps settings in memory; the real one writes to the app support folder.
class _FakeSettings extends SettingsService {
  AppSettings _current = const AppSettings();

  @override
  AppSettings get settings => _current;

  @override
  Future<void> save(AppSettings settings) async => _current = settings;
}

DoctorCheckResolved _resolved(
  String name, {
  DoctorStatus status = DoctorStatus.ok,
  Duration? elapsed,
}) {
  return DoctorCheckResolved(
    name: name,
    status: status,
    title: '$name (detail)',
    summary: 'detail',
    elapsed: elapsed ?? const Duration(milliseconds: 100),
  );
}

/// Lets the cubit's staggered reveal queue drain.
Future<void> _settle() =>
    Future<void>.delayed(FlutterDoctorCubit.revealStagger * 3);

void main() {
  late _FakeRunner runner;
  late _FakeSettings settings;
  late FlutterDoctorCubit cubit;

  setUp(() {
    runner = _FakeRunner();
    settings = _FakeSettings();
    cubit = FlutterDoctorCubit(runner, settings);
  });

  tearDown(() async {
    await cubit.close();
    await runner.close();
  });

  test('pre-renders every expected check as pending', () async {
    await cubit.run();
    expect(cubit.state.isRunning, isTrue);
    expect(cubit.state.checks, hasLength(kDefaultDoctorChecks.length));
    expect(
        cubit.state.checks.every((c) => c.phase == DoctorCheckPhase.pending),
        isTrue);
  });

  test('marks exactly one check running at a time', () async {
    await cubit.run();
    runner.emit(const DoctorCheckStarted('Flutter'));
    await _settle();
    final running =
        cubit.state.checks.where((c) => c.phase == DoctorCheckPhase.running);
    expect(running, hasLength(1));
    expect(running.single.name, 'Flutter');
  });

  test('resolves checks with status, summary and elapsed', () async {
    await cubit.run();
    runner.emit(_resolved('Flutter', elapsed: const Duration(milliseconds: 353)));
    await _settle();
    final flutter =
        cubit.state.checks.firstWhere((c) => c.name == 'Flutter');
    expect(flutter.phase, DoctorCheckPhase.done);
    expect(flutter.status, DoctorStatus.ok);
    expect(flutter.elapsed, const Duration(milliseconds: 353));
    expect(cubit.state.doneCount, 1);
  });

  test('appends a check that was not in the expected list', () async {
    await cubit.run();
    runner.emit(_resolved('Quantum toolchain'));
    await _settle();
    expect(cubit.state.checks.map((c) => c.name), contains('Quantum toolchain'));
  });

  test('attaches detail lines to the right check', () async {
    await cubit.run();
    runner.emit(_resolved('Flutter'));
    runner.emit(const DoctorCheckDetails('Flutter', ['• a', '• b']));
    await _settle();
    final flutter = cubit.state.checks.firstWhere((c) => c.name == 'Flutter');
    expect(flutter.details, ['• a', '• b']);
    expect(flutter.canExpand, isTrue);
  });

  test('completion keeps only resolved rows and persists timings', () async {
    await cubit.run();
    runner.emit(_resolved('Flutter', elapsed: const Duration(seconds: 1)));
    runner.emit(_resolved('Chrome', elapsed: const Duration(milliseconds: 200)));
    await _settle();
    runner.emit(const DoctorRunCompleted(
      passed: 2,
      total: 2,
      totalElapsed: Duration(seconds: 5),
      rawOutput: 'raw',
    ));
    await _settle();

    expect(cubit.state.status, DoctorRunStatus.done);
    expect(cubit.state.checks, hasLength(2));
    expect(cubit.state.elapsed, const Duration(seconds: 5));
    expect(cubit.state.report?.rawOutput, 'raw');
    expect(settings.settings.doctorTimings,
        {'Flutter': 1000, 'Chrome': 200});
  });

  test('progress is weighted by the previous run durations', () async {
    settings.save(const AppSettings(
      doctorTimings: {'Fast': 100, 'Slow': 900},
    ));
    await cubit.run();
    expect(runner.requestedChecks, ['Fast', 'Slow']);

    runner.emit(_resolved('Fast'));
    await _settle();
    // One of two checks done, but only 10% of the expected time.
    expect(cubit.state.progress, closeTo(0.1, 0.001));

    runner.emit(_resolved('Slow'));
    await _settle();
    expect(cubit.state.progress, 1.0);
  });

  test('progress falls back to equal weights on the first ever run', () async {
    await cubit.run();
    runner.emit(_resolved('Flutter'));
    await _settle();
    expect(cubit.state.progress,
        closeTo(1 / kDefaultDoctorChecks.length, 0.001));
  });

  test('cancel turns the running row into an error and keeps the rest',
      () async {
    await cubit.run();
    runner.emit(_resolved('Flutter'));
    runner.emit(const DoctorCheckStarted('Windows Version'));
    await _settle();
    cubit.cancel();
    expect(runner.cancelled, isTrue);
    runner.emit(const DoctorRunFailed('Cancelled', cancelled: true));
    await _settle();

    expect(cubit.state.status, DoctorRunStatus.interrupted);
    final flutter = cubit.state.checks.firstWhere((c) => c.name == 'Flutter');
    final windows =
        cubit.state.checks.firstWhere((c) => c.name == 'Windows Version');
    expect(flutter.status, DoctorStatus.ok);
    expect(windows.status, DoctorStatus.error);
    expect(windows.summary, 'cancelled');
    // Checks that never started stay pending, not errored.
    expect(cubit.state.checks.last.phase, DoctorCheckPhase.pending);
  });

  test('a failure before any row shows the error state', () async {
    await cubit.run();
    runner.emit(const DoctorRunFailed('flutter not found'));
    await _settle();
    expect(cubit.state.status, DoctorRunStatus.failure);
    expect(cubit.state.checks, isEmpty);
    expect(cubit.state.errorMessage, 'flutter not found');
  });

  test('the total stopwatch ticks while running', () async {
    await cubit.run();
    expect(cubit.state.elapsed, Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(cubit.state.elapsed.inMilliseconds, greaterThan(0));
  });
}
