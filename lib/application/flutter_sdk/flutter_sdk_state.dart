part of 'flutter_sdk_cubit.dart';

enum FlutterSdkStatus { initial, loading, ready, notInstalled, failure }

/// Immutable state for the Flutter SDK screen.
class FlutterSdkState extends Equatable {
  const FlutterSdkState({
    this.status = FlutterSdkStatus.initial,
    this.info,
    this.versions = const [],
    this.browsingChannel,
    this.versionsLoading = false,
    this.restorable = const [],
    this.errorMessage,
  });

  final FlutterSdkStatus status;
  final FlutterSdkInfo? info;
  final List<String> versions;

  /// The channel whose versions are currently listed (browsing only — does not
  /// change the active SDK channel).
  final String? browsingChannel;
  final bool versionsLoading;

  /// Recently soft-deleted Flutter SDKs that can still be restored (24h window).
  final List<TrashEntry> restorable;

  final String? errorMessage;

  bool get isLoading => status == FlutterSdkStatus.loading;
  bool get canSwitchVersion => info?.isGitRepo == true;

  FlutterSdkState copyWith({
    FlutterSdkStatus? status,
    FlutterSdkInfo? info,
    List<String>? versions,
    String? browsingChannel,
    bool? versionsLoading,
    List<TrashEntry>? restorable,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FlutterSdkState(
      status: status ?? this.status,
      info: info ?? this.info,
      versions: versions ?? this.versions,
      browsingChannel: browsingChannel ?? this.browsingChannel,
      versionsLoading: versionsLoading ?? this.versionsLoading,
      restorable: restorable ?? this.restorable,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        info,
        versions,
        browsingChannel,
        versionsLoading,
        restorable,
        errorMessage,
      ];
}
