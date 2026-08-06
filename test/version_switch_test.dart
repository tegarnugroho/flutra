import 'package:flutra/application/flutter_sdk/version_switch_cubit.dart';
import 'package:flutra/domain/entities/flutter_release.dart';
import 'package:flutra/domain/entities/flutter_sdk_info.dart';
import 'package:flutra/domain/entities/version_switch.dart';
import 'package:flutter_test/flutter_test.dart';

FlutterRelease _release(String version, String channel) =>
    FlutterRelease(hash: 'abc', channel: channel, version: version);

void main() {
  group('isOfficialFlutterRemote', () {
    test('accepts the https and ssh forms of the official repo', () {
      expect(isOfficialFlutterRemote('https://github.com/flutter/flutter.git'),
          isTrue);
      expect(isOfficialFlutterRemote('https://github.com/flutter/flutter'),
          isTrue);
      expect(isOfficialFlutterRemote('git@github.com:flutter/flutter.git'),
          isTrue);
      expect(isOfficialFlutterRemote('HTTPS://GitHub.com/Flutter/Flutter.git'),
          isTrue);
    });

    test('rejects mirrors, forks and nothing at all', () {
      expect(isOfficialFlutterRemote('https://gitlab.corp/mirror/flutter.git'),
          isFalse);
      expect(isOfficialFlutterRemote('https://github.com/acme/flutter.git'),
          isFalse);
      expect(isOfficialFlutterRemote(null), isFalse);
      expect(isOfficialFlutterRemote('  '), isFalse);
    });
  });

  group('isOfficialFlutterChannel', () {
    test('only the release branches count', () {
      expect(isOfficialFlutterChannel('stable'), isTrue);
      expect(isOfficialFlutterChannel('beta'), isTrue);
      expect(isOfficialFlutterChannel('master'), isTrue);
      expect(isOfficialFlutterChannel('[user-branch]'), isFalse);
      expect(isOfficialFlutterChannel('unknown'), isFalse);
      expect(isOfficialFlutterChannel(null), isFalse);
    });

    test('drives FlutterSdkInfo.isKnownChannel', () {
      const detached = FlutterSdkInfo(version: '3.44.4', channel: '[user-branch]');
      const onStable = FlutterSdkInfo(version: '3.44.4', channel: 'stable');
      expect(detached.isKnownChannel, isFalse);
      expect(onStable.isKnownChannel, isTrue);
    });
  });

  group('switchChannelFor', () {
    test('takes the channel from the release metadata, not the tag name', () {
      expect(switchChannelFor(_release('3.44.4', 'stable')), 'stable');
      expect(switchChannelFor(_release('3.44.4', 'beta')), 'beta');
      // A pre-release tag published on stable still switches onto stable.
      expect(switchChannelFor(_release('3.45.0-1.2.pre', 'stable')), 'stable');
    });

    test('has no branch for master or a retired channel', () {
      expect(switchChannelFor(_release('3.45.0-1.2.pre', 'master')), isNull);
      expect(switchChannelFor(_release('1.22.0', 'dev')), isNull);
      expect(switchChannelFor(_release('3.44.4', '')), isNull);
    });
  });

  group('VersionSwitchOutcome', () {
    test('flags a mirror as a mismatch and the official repo as fine', () {
      const mirror = VersionSwitchOutcome(
        version: '3.44.4',
        channel: 'stable',
        remoteUrl: 'https://gitlab.corp/mirror/flutter.git',
      );
      const official = VersionSwitchOutcome(
        version: '3.44.4',
        channel: 'stable',
        remoteUrl: kFlutterRepoUrl,
      );
      expect(mirror.remoteMismatch, isTrue);
      expect(official.remoteMismatch, isFalse);
    });

    test('assumes the tool cache was rebuilt unless told otherwise', () {
      const outcome =
          VersionSwitchOutcome(version: '3.44.4', channel: 'stable');
      expect(outcome.toolCacheRebuilt, isTrue);
    });
  });

  group('VersionSwitchStep.label', () {
    test('names the version on the checkout step only', () {
      expect(VersionSwitchStep.fetchingTags.label('3.44.4'), 'Fetching tags');
      expect(VersionSwitchStep.checkingOut.label('3.44.4'),
          'Checking out 3.44.4');
      expect(VersionSwitchStep.settingUpstream.label('3.44.4'),
          'Setting upstream');
      expect(VersionSwitchStep.rebuildingCache.label('3.44.4'),
          'Rebuilding tool cache');
      expect(VersionSwitchStep.done.label('3.44.4'), 'Done');
    });
  });

  group('VersionSwitchCubit', () {
    test('ticks off each step and ends on the outcome', () async {
      const outcome = VersionSwitchOutcome(
        version: '3.44.4',
        channel: 'stable',
        stashed: true,
        remoteUrl: kFlutterRepoUrl,
        upstreamSet: true,
      );
      final cubit = VersionSwitchCubit('3.44.4', () => Stream.fromIterable([
            const VersionSwitchStepStarted(VersionSwitchStep.fetchingTags),
            const VersionSwitchLogged('Fetching origin'),
            const VersionSwitchStepStarted(VersionSwitchStep.checkingOut),
            const VersionSwitchStepStarted(VersionSwitchStep.settingUpstream),
            const VersionSwitchStepStarted(VersionSwitchStep.rebuildingCache),
            const VersionSwitchStepStarted(VersionSwitchStep.done),
            const VersionSwitchSucceeded(outcome),
          ]));

      await cubit.run();

      expect(cubit.state.isSuccess, isTrue);
      expect(cubit.state.running, isFalse);
      expect(cubit.state.outcome, outcome);
      expect(cubit.state.completed, VersionSwitchStep.values.toSet());
      expect(cubit.state.lines.single.text, 'Fetching origin');
      await cubit.close();
    });

    test('a failed tool-cache rebuild still counts as a switch', () async {
      const outcome = VersionSwitchOutcome(
        version: '3.44.4',
        channel: 'stable',
        remoteUrl: kFlutterRepoUrl,
        upstreamSet: true,
        toolCacheRebuilt: false,
      );
      final cubit = VersionSwitchCubit('3.44.4', () => Stream.fromIterable([
            const VersionSwitchStepStarted(VersionSwitchStep.rebuildingCache),
            const VersionSwitchLogged('could not rebuild', isError: true),
            const VersionSwitchStepStarted(VersionSwitchStep.done),
            const VersionSwitchSucceeded(outcome),
          ]));

      await cubit.run();

      expect(cubit.state.isSuccess, isTrue);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.outcome?.toolCacheRebuilt, isFalse);
      await cubit.close();
    });

    test('keeps the failed step un-ticked and holds the failure', () async {
      final cubit = VersionSwitchCubit('3.44.4', () => Stream.fromIterable([
            const VersionSwitchStepStarted(VersionSwitchStep.fetchingTags),
            const VersionSwitchStepStarted(VersionSwitchStep.checkingOut),
            const VersionSwitchFailed(
              'Failed to check out Flutter 3.44.4 on the "stable" branch.',
              rolledBack: true,
            ),
          ]));

      await cubit.run();

      expect(cubit.state.isSuccess, isFalse);
      expect(cubit.state.finished, isTrue);
      expect(cubit.state.failure?.rolledBack, isTrue);
      expect(cubit.state.step, VersionSwitchStep.checkingOut);
      expect(cubit.state.completed, {VersionSwitchStep.fetchingTags});
      expect(cubit.state.lines.last.isError, isTrue);
      await cubit.close();
    });

    test('a stream that ends without a verdict counts as a failure', () async {
      final cubit = VersionSwitchCubit('3.44.4', () => Stream.fromIterable([
            const VersionSwitchStepStarted(VersionSwitchStep.fetchingTags),
          ]));

      await cubit.run();

      expect(cubit.state.finished, isTrue);
      expect(cubit.state.isSuccess, isFalse);
      expect(cubit.state.failure, isNotNull);
      await cubit.close();
    });
  });
}
