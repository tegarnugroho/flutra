import 'dart:io';

import 'package:flutra/core/command/system_environment.dart';
import 'package:flutra/core/platform/platform_service.dart';
import 'package:flutra/infrastructure/sdk/flutter_locator.dart';
import 'package:flutra/infrastructure/sdk/sdk_locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('shell environment ignores banners and preserves values', () {
    expect(
      SystemEnvironment.parse(
        'banner\n\x00FLUTRA_ENV\x00PATH=/sdk with spaces/bin:/usr/bin\x00TOKEN=a=b\x00',
      ),
      {'PATH': '/sdk with spaces/bin:/usr/bin', 'TOKEN': 'a=b'},
    );
    expect(SystemEnvironment.parse('unframed output'), isEmpty);
  });

  test('registered SDKs resolve without inherited launcher PATH', () {
    final temp = Directory(
      Directory.systemTemp
          .createTempSync('system_sdks')
          .resolveSymbolicLinksSync(),
    );
    final original = SystemEnvironment.values;
    addTearDown(() {
      SystemEnvironment.values = original;
      temp.deleteSync(recursive: true);
    });
    final flutter = p.join(temp.path, 'flutter');
    Directory(p.join(flutter, 'bin', 'internal')).createSync(recursive: true);
    Directory(
      p.join(flutter, 'packages', 'flutter'),
    ).createSync(recursive: true);
    final executable = p.join(flutter, 'bin', hostPlatform.flutterExecutable);
    File(executable).writeAsStringSync('');
    final android = p.join(temp.path, 'android');
    final tools = Directory(p.join(android, 'platform-tools'))
      ..createSync(recursive: true);
    File(
      p.join(tools.path, hostPlatform.executableName('adb')),
    ).writeAsStringSync('');
    SystemEnvironment.values = {'FLUTTER_ROOT': flutter, 'PATH': tools.path};
    expect(FlutterLocator(hostPlatform).executable, executable);
    expect(SdkLocator(hostPlatform).sdkRoot, android);
    SystemEnvironment.values = {'PATH': p.join(flutter, 'bin')};
    expect(FlutterLocator(hostPlatform).root, flutter);
  });
}
