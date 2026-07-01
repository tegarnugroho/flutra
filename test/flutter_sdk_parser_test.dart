import 'package:android_sdk_manager/infrastructure/repositories/flutter_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterRepositoryImpl.parseSdkInfo', () {
    const json = '''
{
  "frameworkVersion": "3.44.1",
  "channel": "stable",
  "frameworkRevisionShort": "924134a44c",
  "engineRevisionShort": "c416acfeb8",
  "dartSdkVersion": "3.12.1",
  "flutterRoot": "C:\\\\Dev\\\\SDK\\\\flutter"
}''';

    test('reads version, channel and dart version', () {
      final info = FlutterRepositoryImpl.parseSdkInfo(json);
      expect(info.version, '3.44.1');
      expect(info.channel, 'stable');
      expect(info.dartVersion, '3.12.1');
      expect(info.frameworkRevision, '924134a44c');
      expect(info.sdkPath, r'C:\Dev\SDK\flutter');
    });

    test('falls back gracefully on unparseable output', () {
      final info = FlutterRepositoryImpl.parseSdkInfo('not json');
      expect(info.version, 'unknown');
      expect(info.channel, 'unknown');
    });
  });

  group('FlutterRepositoryImpl.parseVersionTags', () {
    test('keeps only clean semver tags by default (stable)', () {
      const raw = '3.24.1\n3.24.0\nv1.0.0\n3.22.0\n3.45.0-1.2.pre\n\n3.19.6';
      final tags = FlutterRepositoryImpl.parseVersionTags(raw);
      expect(tags, ['3.24.1', '3.24.0', '3.22.0', '3.19.6']);
    });

    test('includes pre-release tags for beta/master when requested', () {
      const raw = '3.45.0-1.2.pre\n3.44.1\n3.45.0-0.1.pre\nv2.0.0';
      final tags = FlutterRepositoryImpl.parseVersionTags(raw,
          includePreRelease: true);
      expect(tags, ['3.45.0-1.2.pre', '3.44.1', '3.45.0-0.1.pre']);
    });
  });
}
