part of 'detected_paths_cubit.dart';

/// The resolved on-disk locations of the toolchain.
class DetectedPathsState extends Equatable {
  const DetectedPathsState({
    this.androidSdk,
    this.java,
    this.flutter,
    this.isLoading = false,
  });

  final String? androidSdk;
  final String? java;
  final String? flutter;
  final bool isLoading;

  @override
  List<Object?> get props => [androidSdk, java, flutter, isLoading];
}
