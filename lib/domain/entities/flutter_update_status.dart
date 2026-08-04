import 'package:equatable/equatable.dart';

import 'flutter_release.dart';

/// Whether the local Flutter SDK is behind its channel's newest release.
///
/// Determined by comparing the checkout's HEAD commit with the hash the release
/// index publishes in `current_release`, not by comparing version strings —
/// version strings say nothing about hotfix re-releases.
class FlutterUpdateStatus extends Equatable {
  const FlutterUpdateStatus({
    required this.channel,
    required this.headHash,
    this.installed,
    this.latest,
  });

  final String channel;

  /// The local checkout's HEAD, or null when the SDK isn't a git checkout.
  final String? headHash;

  /// The release [headHash] matches, or null when the commit is unpublished.
  final FlutterRelease? installed;

  /// The channel's newest published release.
  final FlutterRelease? latest;

  /// True only when both hashes are known and differ.
  bool get updateAvailable =>
      headHash != null &&
      headHash!.isNotEmpty &&
      latest != null &&
      latest!.hash != headHash;

  /// True when HEAD is on a commit the index doesn't publish (custom build,
  /// fork, or a local commit on top of a release).
  bool get isUnlistedCommit =>
      headHash != null && headHash!.isNotEmpty && installed == null;

  /// First 7 characters of HEAD, the usual short-hash form.
  String? get shortHash => headHash == null || headHash!.length < 7
      ? headHash
      : headHash!.substring(0, 7);

  @override
  List<Object?> get props => [channel, headHash, installed, latest];
}
