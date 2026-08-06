import 'package:equatable/equatable.dart';

import 'flutter_release.dart';
import 'flutter_sdk_info.dart';

/// The git stash a version switch parks local SDK changes in. Surfaced to the
/// user verbatim so they can `git stash pop` it back.
const String kSwitchStashMessage = 'sdk-manager-auto-stash';

/// The stages of a version switch, in the order they run.
///
/// Flutter reads its channel from the SDK's git branch name, so a switch is not
/// a plain tag checkout: the tag is checked out *onto* its channel branch and
/// the branch is pointed at `origin/<channel>`. Each stage below is one part of
/// that, and each is shown in the progress dialog.
enum VersionSwitchStep {
  /// `git fetch origin --tags --prune` (or `--unshallow` on a shallow clone).
  fetchingTags,

  /// `git checkout -B <channel> refs/tags/<version>`.
  checkingOut,

  /// `git branch --set-upstream-to=origin/<channel> <channel>`.
  settingUpstream,

  /// `flutter --version`, which rebuilds the tool snapshot for the new version.
  /// The only step allowed to fail without failing the switch: the SDK is
  /// already on the right commit and branch by the time it runs.
  rebuildingCache,

  done;

  /// The line shown in the progress list. [version] labels the checkout step.
  String label(String version) => switch (this) {
        VersionSwitchStep.fetchingTags => 'Fetching tags',
        VersionSwitchStep.checkingOut => 'Checking out $version',
        VersionSwitchStep.settingUpstream => 'Setting upstream',
        VersionSwitchStep.rebuildingCache => 'Rebuilding tool cache',
        VersionSwitchStep.done => 'Done',
      };
}

/// The channel branch a release's tag must be checked out onto, or null when
/// the release is on a channel with no switchable branch (`master` rolls
/// forward and publishes no versions; the retired `dev` no longer has one).
///
/// Read from the release index entry rather than guessed from the tag name —
/// `3.44.4` and `3.45.0-1.2.pre` both exist on more than one channel over time.
// TODO: confirm the release index tags every version with its channel for
// pre-2022 releases; entries that far back are missing several other fields.
String? switchChannelFor(FlutterRelease release) {
  final channel = release.channel.trim().toLowerCase();
  if (!isOfficialFlutterChannel(channel) || channel == 'master') return null;
  return channel;
}

/// What a completed switch left behind, for the notices the UI shows after.
class VersionSwitchOutcome extends Equatable {
  const VersionSwitchOutcome({
    required this.version,
    required this.channel,
    this.stashed = false,
    this.remoteUrl,
    this.upstreamSet = false,
    this.toolCacheRebuilt = true,
  });

  final String version;

  /// The branch the SDK now sits on — what `flutter channel` will report.
  final String channel;

  /// Local SDK changes were moved into [kSwitchStashMessage] to allow the
  /// checkout. Never restored automatically.
  final bool stashed;

  /// The `origin` of the SDK checkout, left untouched by the switch.
  final String? remoteUrl;

  /// The channel branch now tracks `origin/<channel>`. False when the remote
  /// has no such branch (a partial mirror), which blocks `flutter upgrade`.
  final bool upstreamSet;

  /// `flutter --version` rebuilt the tool snapshot. False when it could not —
  /// the switch still succeeded, and the next flutter command rebuilds it.
  final bool toolCacheRebuilt;

  /// The SDK is cloned from a fork/mirror, so Flutter still warns about its
  /// upstream even though the channel is now correct.
  bool get remoteMismatch => !isOfficialFlutterRemote(remoteUrl);

  @override
  List<Object?> get props =>
      [version, channel, stashed, remoteUrl, upstreamSet, toolCacheRebuilt];
}

/// One update from a running version switch.
sealed class VersionSwitchEvent {
  const VersionSwitchEvent();
}

/// A new stage began; everything before it succeeded.
class VersionSwitchStepStarted extends VersionSwitchEvent {
  const VersionSwitchStepStarted(this.step);

  final VersionSwitchStep step;
}

/// A line of git/flutter output, or a note from the switch itself.
class VersionSwitchLogged extends VersionSwitchEvent {
  const VersionSwitchLogged(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

/// The switch finished; the SDK is on [outcome].
class VersionSwitchSucceeded extends VersionSwitchEvent {
  const VersionSwitchSucceeded(this.outcome);

  final VersionSwitchOutcome outcome;
}

/// The switch stopped. [rolledBack] tells whether the SDK was returned to the
/// commit it started on — when false, [suggestion] carries the git command the
/// user has to run themselves.
class VersionSwitchFailed extends VersionSwitchEvent {
  const VersionSwitchFailed(
    this.message, {
    this.suggestion,
    this.rolledBack = false,
    this.stashed = false,
  });

  final String message;
  final String? suggestion;
  final bool rolledBack;

  /// Local changes were stashed before the failure and are still stashed.
  final bool stashed;
}
