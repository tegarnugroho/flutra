import 'dart:async';

import 'package:flutra/application/dashboard/dashboard_cubit.dart';
import 'package:flutra/application/toolchain_events.dart';
import 'package:flutra/domain/entities/avd.dart';
import 'package:flutra/domain/entities/device.dart';
import 'package:flutra/domain/entities/environment_snapshot.dart';
import 'package:flutra/domain/entities/sdk_package.dart';
import 'package:flutra/domain/entities/tool_status.dart';
import 'package:flutra/domain/entities/storage_report.dart';
import 'package:flutra/domain/repositories/device_repository.dart';
import 'package:flutra/domain/repositories/emulator_repository.dart';
import 'package:flutra/domain/repositories/environment_repository.dart';
import 'package:flutra/domain/repositories/sdk_repository.dart';
import 'package:flutra/infrastructure/storage/storage_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Detection the test can hold open, so the race with loadOverview is
/// reproducible rather than incidental.
class _Env implements EnvironmentRepository {
  final gate = Completer<EnvironmentSnapshot>();

  @override
  Future<EnvironmentSnapshot> detect({bool forceRefresh = false}) => gate.future;

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// A repository that answers immediately and counts how often it was asked.
class _CountingEnv implements EnvironmentRepository {
  int detections = 0;

  @override
  Future<EnvironmentSnapshot> detect({bool forceRefresh = false}) async {
    detections++;
    return const EnvironmentSnapshot(
      sdk: ToolStatus(kind: ToolKind.sdk, state: ToolState.installed),
      java: ToolStatus(kind: ToolKind.java, state: ToolState.installed),
      flutter: ToolStatus(kind: ToolKind.flutter, state: ToolState.installed),
      emulator: ToolStatus(kind: ToolKind.emulator, state: ToolState.installed),
      adb: ToolStatus(kind: ToolKind.adb, state: ToolState.installed),
      sdkPath: null,
      javaPath: null,
      flutterPath: null,
      platformToolsVersion: null,
      buildToolsVersion: null,
      emulatorVersion: null,
    );
  }

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Emulators implements EmulatorRepository {
  @override
  Future<List<Avd>> listAvds() async => const [
    Avd(name: 'Pixel_8'),
    Avd(name: 'Tablet', isRunning: true),
  ];

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Devices implements DeviceRepository {
  @override
  Future<List<Device>> listDevices() async =>
      const [Device(serial: 'emulator-5554', state: DeviceState.device)];

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Sdk implements SdkRepository {
  @override
  Future<List<SdkPackage>> listPackages() async => const [
    SdkPackage(
      path: 'platform-tools',
      description: 'p',
      state: PackageState.updatable,
    ),
    SdkPackage(
      path: 'emulator',
      description: 'e',
      state: PackageState.installed,
    ),
  ];

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// A service that already holds a fresh report, so loadOverview takes the
/// cached path and never walks a disk in a test.
class _Storage implements StorageAnalysisService {
  _Storage(this.report);

  final StorageReport? report;
  int analyzeCalls = 0;

  @override
  Future<StorageReport?> cached() async => report;

  @override
  bool isStale(StorageReport report) => false;

  @override
  Future<StorageReport> analyze() async {
    analyzeCalls++;
    return report!;
  }

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

EnvironmentSnapshot _snapshot() {
  const tool = ToolStatus(kind: ToolKind.sdk, state: ToolState.installed);
  return const EnvironmentSnapshot(
    sdk: tool,
    java: tool,
    flutter: tool,
    emulator: tool,
    adb: tool,
    sdkPath: r'C:\Sdk',
    javaPath: null,
    flutterPath: null,
    platformToolsVersion: null,
    buildToolsVersion: null,
    emulatorVersion: null,
  );
}

void main() {
  late _Env env;
  late _Storage storage;
  late DashboardCubit cubit;

  setUp(() {
    env = _Env();
    storage = _Storage(
      StorageReport(slices: const [], findings: const [], scannedAt: DateTime(2026)),
    );
    cubit = DashboardCubit(
      env, _Emulators(), _Devices(), _Sdk(), storage, ToolchainEvents());
  });

  tearDown(() => cubit.close());

  test('counts come from the shared repositories', () async {
    await cubit.loadOverview();

    expect(cubit.state.stats?.avdCount, 2);
    expect(cubit.state.stats?.runningAvdCount, 1);
    expect(cubit.state.stats?.updateCount, 1, reason: 'only updatable counts');
    expect(cubit.state.stats?.deviceCount, 1);
    expect(cubit.state.storage, isNotNull);
    expect(storage.analyzeCalls, 0, reason: 'a fresh cache needs no scan');
  });

  test('detection finishing later does not wipe the counts', () async {
    // The page fires both at once; detection is the slower of the two, and a
    // whole-state emit at the end used to drop the stats it never knew about.
    final detection = cubit.refresh();
    await cubit.loadOverview();
    expect(cubit.state.stats, isNotNull);

    env.gate.complete(_snapshot());
    await detection;

    expect(cubit.state.status, DashboardStatus.ready);
    expect(cubit.state.snapshot, isNotNull);
    expect(
      cubit.state.stats,
      isNotNull,
      reason: 'the stat cards would shimmer forever',
    );
    expect(cubit.state.storage, isNotNull);
  });

  test('a toolchain change re-detects without the page being rebuilt', () async {
    // Installing a JDK on the Java page has to change this screen. Navigating
    // back rebuilds the cubit and would re-detect anyway; this covers the case
    // it does not — the Dashboard being the page on screen when it happens.
    final events = ToolchainEvents();
    addTearDown(events.dispose);
    final counting = _CountingEnv();
    final live = DashboardCubit(
      counting, _Emulators(), _Devices(), _Sdk(), _Storage(null), events,
    );
    addTearDown(live.close);

    await live.refresh();
    expect(counting.detections, 1);

    events.emitChanged();
    await Future<void>.delayed(Duration.zero);

    expect(
      counting.detections,
      2,
      reason: 'the Java row would otherwise stay wrong until a restart',
    );
  });

  test('a closed dashboard stops listening for toolchain changes', () async {
    // The cubit outlives nothing, but the bus is a singleton: a subscription
    // left behind would emit into a closed cubit and throw.
    final events = ToolchainEvents();
    addTearDown(events.dispose);
    final counting = _CountingEnv();
    final gone = DashboardCubit(
      counting, _Emulators(), _Devices(), _Sdk(), _Storage(null), events,
    );

    await gone.close();
    events.emitChanged();
    await Future<void>.delayed(Duration.zero);

    expect(counting.detections, 0);
  });

  test('a failing tool contributes zero instead of sinking the overview',
      () async {
    final broken = DashboardCubit(env, _Emulators(), _Devices(), _Sdk(),
        _Storage(null), ToolchainEvents());
    addTearDown(broken.close);

    await broken.loadOverview();
    expect(broken.state.stats, isNotNull);
  });

  test('an unscanned disk says so before the slow tools finish', () async {
    // The panel used to sit on "No scan yet" for the couple of seconds
    // sdkmanager takes, then produce figures out of nowhere. Whether a scan is
    // coming is known from the cache read alone, so it must be published
    // before anything slow is awaited.
    final slowSdk = _SlowSdk();
    final unscanned = _ScanningStorage();
    final cubit = DashboardCubit(
      env,
      _Emulators(),
      _Devices(),
      slowSdk,
      unscanned,
      ToolchainEvents(),
    );
    addTearDown(cubit.close);

    final states = <bool>[];
    final sub = cubit.stream.listen((s) => states.add(s.scanning));
    final overview = cubit.loadOverview();

    // Let the cache read and the first emit settle, with sdkmanager still out.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      cubit.state.scanning,
      isTrue,
      reason: 'the panel has to look busy while the scan is pending',
    );
    expect(cubit.state.stats, isNull, reason: 'the slow tool has not returned');

    slowSdk.gate.complete(const []);
    unscanned.gate.complete(
      StorageReport(slices: const [], findings: const [], scannedAt: DateTime(2026)),
    );
    await overview;
    await sub.cancel();

    expect(cubit.state.scanning, isFalse);
    expect(cubit.state.storage, isNotNull);
    expect(states.first, isTrue, reason: 'busy from the very first emit');
  });
}

/// sdkmanager, held open — it is the slowest call in the overview.
class _SlowSdk implements SdkRepository {
  final gate = Completer<List<SdkPackage>>();

  @override
  Future<List<SdkPackage>> listPackages() => gate.future;

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// A machine that has never been scanned, with the walk held open.
class _ScanningStorage implements StorageAnalysisService {
  final gate = Completer<StorageReport>();

  @override
  Future<StorageReport?> cached() async => null;

  @override
  bool isStale(StorageReport report) => true;

  @override
  Future<StorageReport> analyze() => gate.future;

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}
