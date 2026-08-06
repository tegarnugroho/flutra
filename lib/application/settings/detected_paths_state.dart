part of 'detected_paths_cubit.dart';

/// The resolved on-disk locations of the toolchain.
class DetectedPathsState extends Equatable {
  const DetectedPathsState({
    this.androidSdk,
    this.java,
    this.flutter,
    this.isLoading = false,
    this.isScanning = false,
    this.scanned = false,
    this.androidCandidates = const [],
    this.flutterCandidates = const [],
  });

  /// SDK *roots*, never the executables inside them.
  final String? androidSdk;
  final String? java;
  final String? flutter;

  final bool isLoading;

  /// A disk scan is walking directories right now.
  final bool isScanning;

  /// At least one scan has finished, so empty candidate lists mean "searched
  /// and found nothing" rather than "never looked".
  final bool scanned;

  /// Every install the last scan turned up, for the picker.
  final List<String> androidCandidates;
  final List<String> flutterCandidates;

  DetectedPathsState copyWith({
    String? androidSdk,
    String? java,
    String? flutter,
    bool? isLoading,
    bool? isScanning,
    bool? scanned,
    List<String>? androidCandidates,
    List<String>? flutterCandidates,
  }) {
    return DetectedPathsState(
      androidSdk: androidSdk ?? this.androidSdk,
      java: java ?? this.java,
      flutter: flutter ?? this.flutter,
      isLoading: isLoading ?? this.isLoading,
      isScanning: isScanning ?? this.isScanning,
      scanned: scanned ?? this.scanned,
      androidCandidates: androidCandidates ?? this.androidCandidates,
      flutterCandidates: flutterCandidates ?? this.flutterCandidates,
    );
  }

  @override
  List<Object?> get props => [
        androidSdk,
        java,
        flutter,
        isLoading,
        isScanning,
        scanned,
        androidCandidates,
        flutterCandidates,
      ];
}
