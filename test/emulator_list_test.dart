import 'package:flutra/application/emulator/emulator_list_cubit.dart';
import 'package:flutra/core/command/command_runner.dart';
import 'package:flutra/domain/entities/avd.dart';
import 'package:flutra/domain/entities/avd_create_request.dart';
import 'package:flutra/domain/entities/device_definition.dart';
import 'package:flutra/domain/entities/system_image.dart';
import 'package:flutra/domain/repositories/emulator_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves whatever list the test sets, and records what was asked of it.
class _FakeEmulatorRepository implements EmulatorRepository {
  _FakeEmulatorRepository(this.avds);

  List<Avd> avds;
  final calls = <String>[];

  @override
  Future<List<Avd>> listAvds() async => avds;

  @override
  Future<void> stop(String name) async {
    calls.add('stop:$name');
    avds = [
      for (final avd in avds)
        if (avd.name == name) avd.copyWith(isRunning: false) else avd,
    ];
  }

  @override
  Future<void> wipeData(String name) async => calls.add('wipe:$name');

  @override
  Future<void> deleteAvd(String name) async {
    calls.add('delete:$name');
    avds = [
      for (final avd in avds)
        if (avd.name != name) avd,
    ];
  }

  @override
  Future<void> duplicateAvd(String source, String newName) async {
    calls.add('duplicate:$source→$newName');
    avds = [...avds, Avd(name: newName)];
  }

  @override
  Future<String> renameAvd(String source, String newName) async {
    calls.add('rename:$source→$newName');
    // The real one sanitises, and the cubit has to follow the name it gets
    // back rather than the one it asked for.
    final target = newName.replaceAll(' ', '_');
    avds = [
      for (final avd in avds)
        if (avd.name == source) Avd(name: target) else avd,
    ];
    return target;
  }

  @override
  Future<RunningCommand> launch(String name, LaunchOptions options) =>
      throw UnimplementedError();

  @override
  Future<void> createAvd(AvdCreateRequest request) => throw UnimplementedError();

  @override
  Future<List<DeviceDefinition>> listDeviceDefinitions() =>
      throw UnimplementedError();

  @override
  Future<List<SystemImage>> listSystemImages() => throw UnimplementedError();
}

List<String> _names(EmulatorListCubit cubit) =>
    [for (final avd in cubit.state.avds) avd.name];

void main() {
  group('ordering', () {
    test('running devices sort first, the rest by name', () async {
      final repo = _FakeEmulatorRepository(const [
        Avd(name: 'zebra'),
        Avd(name: 'Alpha'),
        Avd(name: 'pixel', isRunning: true),
        Avd(name: 'beta'),
      ]);
      final cubit = EmulatorListCubit(repo);

      await cubit.load();

      expect(_names(cubit), ['pixel', 'Alpha', 'beta', 'zebra']);
      await cubit.close();
    });

    test('a device that starts does not jump the list under the pointer',
        () async {
      final repo = _FakeEmulatorRepository(const [
        Avd(name: 'alpha'),
        Avd(name: 'beta'),
        Avd(name: 'gamma'),
      ]);
      final cubit = EmulatorListCubit(repo);
      await cubit.load();
      expect(_names(cubit), ['alpha', 'beta', 'gamma']);

      // gamma comes up between reloads; the reload after an action keeps the
      // order the user is looking at.
      repo.avds = const [
        Avd(name: 'alpha'),
        Avd(name: 'beta'),
        Avd(name: 'gamma', isRunning: true),
      ];
      await cubit.load(resort: false);

      expect(_names(cubit), ['alpha', 'beta', 'gamma']);
      expect(cubit.state.runningCount, 1);
      await cubit.close();
    });

    test('an explicit refresh is what re-sorts', () async {
      final repo = _FakeEmulatorRepository(const [
        Avd(name: 'alpha'),
        Avd(name: 'beta'),
        Avd(name: 'gamma', isRunning: true),
      ]);
      final cubit = EmulatorListCubit(repo);
      await cubit.load(resort: false);
      await cubit.load();

      expect(_names(cubit), ['gamma', 'alpha', 'beta']);
      await cubit.close();
    });

    test('a device created since the last sort lands at the end', () async {
      final repo = _FakeEmulatorRepository(const [
        Avd(name: 'alpha'),
        Avd(name: 'beta'),
      ]);
      final cubit = EmulatorListCubit(repo);
      await cubit.load();

      await cubit.duplicate(const Avd(name: 'alpha'), 'aaa_copy');

      expect(repo.calls, contains('duplicate:alpha→aaa_copy'));
      // Sorted by name it would be first; it stays out of the way until the
      // next refresh.
      expect(_names(cubit), ['alpha', 'beta', 'aaa_copy']);
      await cubit.close();
    });

    test('a renamed device keeps its place in the list', () async {
      final repo = _FakeEmulatorRepository(const [
        Avd(name: 'alpha'),
        Avd(name: 'beta'),
        Avd(name: 'gamma'),
      ]);
      final cubit = EmulatorListCubit(repo);
      await cubit.load();

      // Sanitised to "zulu_one", which sorts last — the row still must not
      // move out from under the pointer that just opened its menu.
      await cubit.rename(const Avd(name: 'beta'), 'zulu one');

      expect(repo.calls, contains('rename:beta→zulu one'));
      expect(_names(cubit), ['alpha', 'zulu_one', 'gamma']);
      await cubit.close();
    });

    test('a deleted device leaves without disturbing the others', () async {
      final repo = _FakeEmulatorRepository(const [
        Avd(name: 'alpha'),
        Avd(name: 'beta'),
        Avd(name: 'gamma'),
      ]);
      final cubit = EmulatorListCubit(repo);
      await cubit.load();

      await cubit.delete(const Avd(name: 'beta'));

      expect(_names(cubit), ['alpha', 'gamma']);
      await cubit.close();
    });
  });

  group('tasks', () {
    test('an in-flight operation names itself, then clears', () async {
      final repo = _FakeEmulatorRepository(const [
        Avd(name: 'alpha', isRunning: true),
      ]);
      final cubit = EmulatorListCubit(repo);
      await cubit.load();

      final tasks = <AvdTask?>[];
      final sub = cubit.stream.listen((s) => tasks.add(s.taskFor('alpha')));
      await cubit.stop(const Avd(name: 'alpha', isRunning: true));
      await sub.cancel();

      expect(tasks, contains(AvdTask.stopping));
      expect(cubit.state.taskFor('alpha'), isNull);
      expect(cubit.state.isBusy('alpha'), isFalse);
      await cubit.close();
    });

    test('the label is the present tense of what is happening', () {
      expect(AvdTask.starting.label, 'Starting…');
      expect(AvdTask.stopping.label, 'Stopping…');
      expect(AvdTask.wiping.label, 'Wiping…');
    });
  });

  group('countLabel', () {
    EmulatorListState stateOf(List<Avd> avds) =>
        EmulatorListState(avds: avds);

    test('counts devices, and running ones only when there are some', () {
      expect(
        stateOf(const [Avd(name: 'a'), Avd(name: 'b')]).countLabel,
        '2 devices',
      );
      expect(
        stateOf(const [
          Avd(name: 'a', isRunning: true),
          Avd(name: 'b'),
          Avd(name: 'c'),
          Avd(name: 'd'),
        ]).countLabel,
        '4 devices · 1 running',
      );
    });

    test('one device is not "1 devices"', () {
      expect(stateOf(const [Avd(name: 'a')]).countLabel, '1 device');
    });
  });
}
