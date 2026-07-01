import 'package:android_sdk_manager/application/dashboard/dashboard_cubit.dart';
import 'package:android_sdk_manager/domain/entities/environment_snapshot.dart';
import 'package:android_sdk_manager/domain/entities/tool_status.dart';
import 'package:android_sdk_manager/domain/repositories/environment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements EnvironmentRepository {
  _FakeRepo(this._snapshot);
  final EnvironmentSnapshot _snapshot;
  @override
  Future<EnvironmentSnapshot> detect() async => _snapshot;
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

void main() {
  group('DashboardCubit', () {
    test('emits ready with snapshot on successful detection', () async {
      final cubit = DashboardCubit(_FakeRepo(_snapshot(ready: true)));
      await cubit.refresh();

      expect(cubit.state.status, DashboardStatus.ready);
      expect(cubit.state.snapshot?.isReady, isTrue);
      addTearDown(cubit.close);
    });

    test('reports missing tools when environment is incomplete', () async {
      final cubit = DashboardCubit(_FakeRepo(_snapshot(ready: false)));
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
