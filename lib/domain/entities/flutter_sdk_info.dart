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

  /// True when the SDK is on an official channel. False for detached/version
  /// checkouts, which Flutter reports as "[user-branch]" or "unknown".
  bool get isKnownChannel => kFlutterChannels.contains(channel);

  @override
  List<Object?> get props =>
      [version, channel, dartVersion, frameworkRevision, sdkPath, isGitRepo];
}

/// The standard Flutter release channels.
const List<String> kFlutterChannels = ['stable', 'beta', 'master'];
