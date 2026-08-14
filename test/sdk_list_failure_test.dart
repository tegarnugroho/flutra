import 'dart:io';

import 'package:flutra/core/command/command_result.dart';
import 'package:flutra/core/command/command_runner.dart';
import 'package:flutra/core/command/sdk_operation_lock.dart';
import 'package:flutra/core/command/session_environment.dart';
import 'package:flutra/core/error/failures.dart';
import 'package:flutra/core/platform/platform_service.dart';
import 'package:flutra/infrastructure/repositories/sdk_repository_impl.dart';
import 'package:flutra/infrastructure/sdk/android_tool_runner.dart';
import 'package:flutra/infrastructure/sdk/sdk_locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// An [AndroidToolRunner] that spawns nothing and answers with [result].
///
/// The behaviour under test is what the repository does with what sdkmanager
/// said, so what it says is the input.
class _StubRunner extends AndroidToolRunner {
  _StubRunner(this.result)
      : super.ambient(CommandRunner(SessionEnvironment()));

  final CommandResult result;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Duration? timeout,
    bool runInShell = true,
  }) async {
    invocations.add(arguments);
    return result;
  }

  final List<List<String>> invocations = [];
}

CommandResult resultOf({
  int exitCode = 0,
  String stdout = '',
  String stderr = '',
}) =>
    CommandResult(
      executable: 'sdkmanager',
      arguments: const ['--list'],
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      duration: Duration.zero,
    );

void main() {
  late Directory temp;
  late SdkLocator locator;

  /// The smallest thing [SdkLocator] accepts as an SDK with tools in it.
  setUp(() {
    temp = Directory.systemTemp.createTempSync('sdk_list_failure_');
    final platform = hostPlatform;
    final bin = Directory(p.join(temp.path, 'cmdline-tools', 'latest', 'bin'))
      ..createSync(recursive: true);
    File(p.join(bin.path, platform.scriptName('sdkmanager')))
        .writeAsStringSync('');
    locator = SdkLocator(platform)..overrideSdkRoot = temp.path;
  });

  tearDown(() => temp.deleteSync(recursive: true));

  SdkRepositoryImpl repositoryFor(_StubRunner runner) =>
      SdkRepositoryImpl(runner, locator, SdkOperationLock());

  group('listPackages surfaces a failed query instead of an empty catalogue',
      () {
    test('the JAVA_HOME error on stdout is a failure, not zero packages', () {
      // Captured from a Linux box whose only JDK was the one Flutra manages —
      // which is on neither PATH nor JAVA_HOME. Note the exit code is 1, stderr
      // is empty and the message is on *stdout*: a guard that only fired on
      // "failed and printed nothing" let this straight through to the parser,
      // which found no packages in it and reported an empty SDK.
      const message = '\n'
          "ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.\n"
          '\n'
          'Please set the JAVA_HOME variable in your environment to match the\n'
          'location of your Java installation.\n';
      final repository =
          repositoryFor(_StubRunner(resultOf(exitCode: 1, stdout: message)));

      expect(
        repository.listPackages(),
        throwsA(
          isA<ProcessFailure>()
              .having((e) => e.exitCode, 'exitCode', 1)
              .having((e) => e.output, 'output', contains('JAVA_HOME')),
        ),
      );
    });

    test('exit 0 with output that holds no section is a failure', () {
      // A truncated or garbled run: nothing to parse, and nothing that proves
      // the query ever reached the repository.
      final repository = repositoryFor(
        _StubRunner(resultOf(stdout: 'Loading package information...\n')),
      );

      expect(repository.listPackages(), throwsA(isA<ProcessFailure>()));
    });

    test('a failure with no output at all still says something', () {
      final repository = repositoryFor(_StubRunner(resultOf(exitCode: 137)));

      expect(
        repository.listPackages(),
        throwsA(isA<ProcessFailure>()
            .having((e) => e.output, 'output', isNotEmpty)),
      );
    });

    test('a non-zero exit is a failure even when the listing parsed', () {
      // sdkmanager exits non-zero on a repository it could not fully read. Half
      // a catalogue shown as the whole one is the version of this bug that is
      // hardest to notice.
      final repository = repositoryFor(_StubRunner(resultOf(
        exitCode: 1,
        stdout: 'Available Packages:\n'
            '  Path | Version | Description\n'
            '  platform-tools | 34.0.5 | Android SDK Platform-Tools\n',
      )));

      expect(repository.listPackages(), throwsA(isA<ProcessFailure>()));
    });
  });

  group('listPackages accepts the runs that worked', () {
    test('an SDK with nothing installed is empty, not broken', () async {
      // The state a fresh bootstrap leaves behind: no "Installed packages"
      // section, a full remote catalogue, and every package available.
      final repository = repositoryFor(_StubRunner(resultOf(
        stdout: File('test/fixtures/sdkmanager_list_linux.txt')
            .readAsStringSync(),
      )));

      final packages = await repository.listPackages();
      expect(packages, isNotEmpty);
      expect(packages.map((p) => p.path), contains('platform-tools'));
    });

    test('the deprecation warning on stderr is not a failure', () async {
      // Current cmdline-tools print this on every successful run. Treating a
      // non-empty stderr as failure would break every listing.
      final repository = repositoryFor(_StubRunner(resultOf(
        stdout: File('test/fixtures/sdkmanager_list_linux.txt')
            .readAsStringSync(),
        stderr: 'WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated. '
            'Use Android CLI instead.',
      )));

      expect(await repository.listPackages(), isNotEmpty);
    });

    test('asks for the stable channel explicitly', () async {
      final runner = _StubRunner(resultOf(
        stdout: File('test/fixtures/sdkmanager_list_linux.txt')
            .readAsStringSync(),
      ));
      await repositoryFor(runner).listPackages();

      expect(runner.invocations.single, contains('--list'));
      expect(runner.invocations.single, contains('--channel=0'));
    });
  });
}
