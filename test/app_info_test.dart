import 'package:android_sdk_manager/core/constants/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('diagnostic block', () {
    test('leads with the app, version and build', () {
      final lines = AppInfo.diagnosticBlock().split('\n');
      expect(
        lines.first,
        '${AppInfo.name} ${AppInfo.version} (build ${AppInfo.buildNumber})',
      );
      expect(lines[1], startsWith('Channel: ${AppInfo.channel}'));
    });

    test('omits lines the build did not supply', () {
      // A dev run defines none of the build-time values, so neither the
      // toolchain nor the commit line may appear — a block full of dashes is
      // worse than a short one.
      final block = AppInfo.diagnosticBlock();
      if (AppInfo.commit == AppInfo.unknown) {
        expect(block, isNot(contains('Commit:')));
      }
      if (AppInfo.flutterVersion == AppInfo.unknown &&
          AppInfo.dartVersion == AppInfo.unknown) {
        expect(block, isNot(contains('Flutter:')));
      }
      expect(block, isNot(contains('${AppInfo.unknown}\n')));
    });
  });

  group('metadata', () {
    test('every link is an https URL under the repository', () {
      for (final url in [
        AppInfo.repositoryUrl,
        AppInfo.issuesUrl,
        AppInfo.releaseNotesUrl,
      ]) {
        final uri = Uri.parse(url);
        expect(uri.scheme, 'https');
        expect(uri.host, isNotEmpty);
      }
      expect(AppInfo.issuesUrl, startsWith(AppInfo.repositoryUrl));
      expect(AppInfo.releaseNotesUrl, startsWith(AppInfo.repositoryUrl));
    });

    test('the platform label names the OS', () {
      expect(AppInfo.platformLabel, isNot(AppInfo.unknown));
      expect(AppInfo.platformLabel, isNotEmpty);
    });

    test('copyright carries the current year, author and licence', () {
      final copyright = AppInfo.copyright;
      expect(copyright, contains(DateTime.now().year.toString()));
      expect(copyright, contains(AppInfo.author));
      expect(copyright, contains(AppInfo.license));
    });
  });

  group('runtime-derived values', () {
    test('Dart version is read from the VM, never a dash', () {
      // The runtime is the build for Dart, so this needs no --dart-define and
      // must be populated even in a plain `flutter test` run.
      expect(AppInfo.dartVersion, isNot(AppInfo.unknown));
      expect(AppInfo.dartVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
    });

    test('the diagnostic block carries the Dart version it found', () {
      expect(AppInfo.diagnosticBlock(), contains(AppInfo.dartVersion));
    });
  });
}
