import 'package:equatable/equatable.dart';

/// Details of the currently-active Flutter SDK, from `flutter --version`.
class FlutterSdkInfo extends Equatable {
  const FlutterSdkInfo({
    required this.version,
    required this.channel,
    this.dartVersion,
    this.frameworkRevision,
    this.engineRevision,
    this.sdkPath,
    this.isGitRepo = false,
    this.remoteUrl,
  });

  /// Framework version, e.g. "3.44.1".
  final String version;

  /// Active channel, e.g. "stable", "beta", "master".
  final String channel;

  final String? dartVersion;
  final String? frameworkRevision;
  final String? engineRevision;

  /// Absolute path to the Flutter SDK root.
  final String? sdkPath;

  /// Whether the SDK root is a git checkout (required to switch versions).
  final bool isGitRepo;

  /// The `origin` remote URL of the SDK git repo, if known.
  final String? remoteUrl;

  /// True when the upstream remote points at the official Flutter repo.
  bool get isStandardRemote =>
      remoteUrl != null && remoteUrl!.contains('github.com/flutter/flutter');

  /// True when the SDK is on an official channel. False for detached/version
  /// checkouts, which Flutter reports as "[user-branch]" or "unknown".
  bool get isKnownChannel => kFlutterChannels.contains(channel);

  FlutterSdkInfo copyWith({String? remoteUrl}) => FlutterSdkInfo(
        version: version,
        channel: channel,
        dartVersion: dartVersion,
        frameworkRevision: frameworkRevision,
        engineRevision: engineRevision,
        sdkPath: sdkPath,
        isGitRepo: isGitRepo,
        remoteUrl: remoteUrl ?? this.remoteUrl,
      );

  @override
  List<Object?> get props => [
        version,
        channel,
        dartVersion,
        frameworkRevision,
        sdkPath,
        isGitRepo,
        remoteUrl,
      ];
}

/// The standard Flutter release channels.
const List<String> kFlutterChannels = ['stable', 'beta', 'master'];
