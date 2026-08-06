import 'package:flutra/application/dashboard/dashboard_cubit.dart';
import 'package:flutra/domain/entities/environment_snapshot.dart';
import 'package:flutra/domain/entities/tool_status.dart';
import 'package:flutra/domain/repositories/device_repository.dart';
import 'package:flutra/domain/repositories/emulator_repository.dart';
import 'package:flutra/domain/repositories/environment_repository.dart';
import 'package:flutra/domain/repositories/sdk_repository.dart';
import 'package:flutra/infrastructure/storage/storage_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements EnvironmentRepository {
  _FakeRepo(this._snapshot);
  final EnvironmentSnapshot _snapshot;
  @override
  Future<EnvironmentSnapshot> detect({bool forceRefresh = false}) async =>
      _snapshot;
}

EnvironmentSnapshot _snapshot({required bool ready}) {
  ToolStatus s(ToolKind k) => ToolStatus(
    kind: k,
    state: ready ? ToolState.installed : ToolState.missing,
  );
  return EnvironmentSnapshot(
    sdk: s(ToolKind.sdk),
    java: s(ToolKind.java),
    flutter: s(ToolKind.flutter),
    emulator: s(ToolKind.emulator),
    adb: s(ToolKind.adb),
    sdkPath: ready ? r'C:\Android\Sdk' : null,
    javaPath: null,
    flutterPath: null,
    platformToolsVersion: null,
    buildToolsVersion: null,
    emulatorVersion: null,
  );
}

/// The dashboard also reads counts and disk usage; these tests only exercise
/// toolchain detection, so the rest are stubs that are never called.
DashboardCubit _cubit(EnvironmentSnapshot snapshot) => DashboardCubit(
  _FakeRepo(snapshot),
  _Unused(),
  _Unused(),
  _Unused(),
  _Unused(),
);

class _Unused
    implements
        EmulatorRepository,
        DeviceRepository,
        SdkRepository,
        StorageAnalysisService {
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  group('DashboardCubit', () {
    test('emits ready with snapshot on successful detection', () async {
      final cubit = _cubit(_snapshot(ready: true));
      await cubit.refresh();

      expect(cubit.state.status, DashboardStatus.ready);
      expect(cubit.state.snapshot?.isReady, isTrue);
      addTearDown(cubit.close);
    });

    test('reports missing tools when environment is incomplete', () async {
      final cubit = _cubit(_snapshot(ready: false));
      await cubit.refresh();

      expect(cubit.state.snapshot?.isReady, isFalse);
      expect(
        cubit.state.snapshot?.all.every((t) => t.state == ToolState.missing),
        isTrue,
      );
      addTearDown(cubit.close);
    });
  });
}
