import 'dart:io';

import 'package:flutra/core/command/command_runner.dart';
import 'package:flutra/core/command/session_environment.dart';
import 'package:flutra/core/error/failures.dart';
import 'package:flutra/core/platform/platform_service.dart';
import 'package:flutra/infrastructure/repositories/emulator_repository_impl.dart';
import 'package:flutra/infrastructure/sdk/sdk_locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The real repository, pointed at [avdHome] through the same environment
/// variable the emulator itself reads. Renaming touches only the filesystem, so
/// no tool is ever spawned and the runner and locator are never asked anything.
EmulatorRepositoryImpl repositoryAt(String avdHome) {
  final environment = {'ANDROID_AVD_HOME': avdHome};
  final PlatformService platform = Platform.isWindows
      ? WindowsPlatformService(environment: environment)
      : LinuxPlatformService(environment: environment);
  return EmulatorRepositoryImpl(
    CommandRunner(SessionEnvironment()),
    SdkLocator(platform),
    platform,
  );
}

void main() {
  group('renameAvd', () {
    late Directory avdHome;
    late EmulatorRepositoryImpl repository;

    /// Lays down the pair on disk that makes an AVD: `<name>.ini` pointing at
    /// `<name>.avd`, and a config.ini inside it.
    void createAvd(String name, {String displayName = ''}) {
      final dir = Directory(p.join(avdHome.path, '$name.avd'))
        ..createSync(recursive: true);
      File(p.join(avdHome.path, '$name.ini')).writeAsStringSync(
        'avd.ini.encoding=UTF-8\n'
        'path=${p.join(avdHome.path, '$name.avd')}\n'
        'path.rel=avd/$name.avd\n'
        'target=android-34\n',
      );
      File(p.join(dir.path, 'config.ini')).writeAsStringSync(
        'AvdId=$name\n'
        'avd.ini.displayname=${displayName.isEmpty ? name : displayName}\n'
        'hw.lcd.density=440\n'
        'sdcard.path=${p.join(dir.path, 'sdcard.img')}\n',
      );
    }

    String iniOf(String name) =>
        File(p.join(avdHome.path, '$name.ini')).readAsStringSync();

    String configOf(String name) =>
        File(p.join(avdHome.path, '$name.avd', 'config.ini')).readAsStringSync();

    setUp(() {
      avdHome = Directory.systemTemp.createTempSync('avd_rename_');
      repository = repositoryAt(avdHome.path);
    });
    tearDown(() => avdHome.deleteSync(recursive: true));

    test('moves both halves of the AVD and leaves nothing behind', () async {
      createAvd('Pixel_8');

      final name = await repository.renameAvd('Pixel_8', 'Pixel_8_API_34');

      expect(name, 'Pixel_8_API_34');
      expect(Directory(p.join(avdHome.path, 'Pixel_8_API_34.avd')).existsSync(),
          isTrue);
      expect(File(p.join(avdHome.path, 'Pixel_8_API_34.ini')).existsSync(),
          isTrue);
      expect(Directory(p.join(avdHome.path, 'Pixel_8.avd')).existsSync(),
          isFalse);
      expect(File(p.join(avdHome.path, 'Pixel_8.ini')).existsSync(), isFalse);
    });

    test('rewrites the paths the ini holds, so the tools still find it',
        () async {
      createAvd('Pixel_8');

      await repository.renameAvd('Pixel_8', 'Renamed');

      final ini = iniOf('Renamed');
      expect(ini, contains(p.join(avdHome.path, 'Renamed.avd')));
      expect(ini, contains('path.rel=avd/Renamed.avd'));
      expect(ini, isNot(contains('Pixel_8.avd')));
      // Everything else in the file is left exactly as it was.
      expect(ini, contains('target=android-34'));
    });

    test('renames the AVD inside its own config.ini too', () async {
      createAvd('Pixel_8', displayName: 'Pixel 8');

      await repository.renameAvd('Pixel_8', 'Renamed');

      final config = configOf('Renamed');
      expect(config, contains('AvdId=Renamed'));
      expect(config, contains('avd.ini.displayname=Renamed'));
      // An absolute path into the old directory would be left dangling.
      expect(config, contains(p.join(avdHome.path, 'Renamed.avd', 'sdcard.img')));
      expect(config, contains('hw.lcd.density=440'));
    });

    test('replaces the characters avdmanager will not take', () async {
      createAvd('Pixel_8');

      final name = await repository.renameAvd('Pixel_8', 'My Pixel!');

      expect(name, 'My_Pixel_');
      expect(configOf('My_Pixel_'), contains('AvdId=My_Pixel_'));
    });

    test('a name that sanitises to the current one is a no-op, not a clash',
        () async {
      createAvd('My_Pixel');

      final name = await repository.renameAvd('My_Pixel', 'My Pixel');

      expect(name, 'My_Pixel');
      expect(configOf('My_Pixel'), contains('AvdId=My_Pixel'));
    });

    test('refuses a name another AVD already holds, and moves nothing',
        () async {
      createAvd('Pixel_8');
      createAvd('Tablet');

      await expectLater(
        repository.renameAvd('Pixel_8', 'Tablet'),
        throwsA(isA<FileSystemFailure>()),
      );

      expect(Directory(p.join(avdHome.path, 'Pixel_8.avd')).existsSync(),
          isTrue);
      expect(configOf('Tablet'), contains('AvdId=Tablet'));
    });

    test('an empty name is refused before anything is touched', () async {
      createAvd('Pixel_8');

      await expectLater(
        repository.renameAvd('Pixel_8', '   '),
        throwsA(isA<FileSystemFailure>()),
      );
      expect(File(p.join(avdHome.path, 'Pixel_8.ini')).existsSync(), isTrue);
    });

    test('an AVD that is not there cannot be renamed', () async {
      await expectLater(
        repository.renameAvd('Ghost', 'Anything'),
        throwsA(isA<FileSystemFailure>()),
      );
    });
  });
}
