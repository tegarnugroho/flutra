import 'dart:io';

import 'package:flutra/core/command/command_result.dart';
import 'package:flutra/core/command/command_runner.dart';
import 'package:flutra/core/command/session_environment.dart';
import 'package:flutra/core/platform/platform_service.dart';
import 'package:flutra/infrastructure/java/jdk_detection_service.dart';
import 'package:flutra/infrastructure/java/jdk_install_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Installs implements JdkInstallService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runner extends CommandRunner {
  _Runner(this.home) : super(SessionEnvironment());
  final String home;

  @override
  Future<String?> which(String executable) async => '/usr/bin/java';

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    bool runInShell = true,
  }) async {
    expect(executable, '/usr/libexec/java_home');
    expect(timeout, isNotNull);
    return CommandResult(
      executable: executable,
      arguments: arguments,
      exitCode: 0,
      stdout: '$home\n',
      stderr: '',
      duration: Duration.zero,
    );
  }
}

void main() {
  test(
    'macOS Java launcher resolves to a real JDK and cannot be activated as /usr',
    () async {
      final temp = Directory.systemTemp.createTempSync('macos_jdk');
      addTearDown(() => temp.deleteSync(recursive: true));
      Directory(p.join(temp.path, 'bin')).createSync();
      File(p.join(temp.path, 'bin', 'java')).writeAsStringSync('');
      final detection = JdkDetectionService(
        _Runner(temp.path),
        MacosPlatformService(),
        _Installs(),
      );
      expect(detection.looksLikeJavaHome('/usr'), isFalse);
      expect(await detection.pathJdkHome(), temp.path);
    },
  );
}
