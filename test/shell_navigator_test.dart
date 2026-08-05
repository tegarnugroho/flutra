import 'package:android_sdk_manager/application/shell/shell_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ShellNavigator navigator;

  setUp(() => navigator = ShellNavigator());
  tearDown(() => navigator.dispose());

  test('emits the destination a caller asked for', () async {
    final seen = <ShellDestination>[];
    final sub = navigator.onNavigate.listen((r) => seen.add(r.destination));

    navigator.go(ShellDestination.updates);
    navigator.go(ShellDestination.devices);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, [ShellDestination.updates, ShellDestination.devices]);
  });

  test('autoRun is claimed exactly once', () {
    navigator.go(ShellDestination.flutterDoctor, autoRun: true);

    // The page builds after the event and claims the flag as it does.
    expect(navigator.consumeAutoRun(ShellDestination.flutterDoctor), isTrue);
    // A rebuild must not start a second run.
    expect(navigator.consumeAutoRun(ShellDestination.flutterDoctor), isFalse);
  });

  test('plain navigation leaves nothing to claim', () {
    navigator.go(ShellDestination.flutterDoctor);
    expect(navigator.consumeAutoRun(ShellDestination.flutterDoctor), isFalse);
  });

  test('an autoRun for one screen is not claimable by another', () {
    navigator.go(ShellDestination.flutterDoctor, autoRun: true);
    expect(navigator.consumeAutoRun(ShellDestination.sdkManager), isFalse);
    expect(navigator.consumeAutoRun(ShellDestination.flutterDoctor), isTrue);
  });

  test('going nowhere after dispose is a no-op, not a crash', () {
    navigator.dispose();
    navigator.go(ShellDestination.dashboard);
  });
}
