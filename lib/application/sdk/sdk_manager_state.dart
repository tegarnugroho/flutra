part of 'sdk_manager_cubit.dart';

enum SdkManagerStatus { initial, loading, ready, failure }

/// Immutable state for the SDK Manager, including active filters.
class SdkManagerState extends Equatable {
  const SdkManagerState({
    this.status = SdkManagerStatus.initial,
    this.packages = const [],
    this.query = '',
    this.category,
    this.updatesOnly = false,
    this.installedOnly = false,
    this.errorMessage,
  });

  final SdkManagerStatus status;
  final List<SdkPackage> packages;
  final String query;
  final PackageCategory? category;
  final bool updatesOnly;
  final bool installedOnly;
  final String? errorMessage;

  bool get isLoading => status == SdkManagerStatus.loading;

  int get updateCount => packages.where((p) => p.hasUpdate).length;
  int get installedCount => packages.where((p) => p.isInstalled).length;

  /// Categories present in the loaded catalogue, in enum order.
  List<PackageCategory> get availableCategories {
    final present = packages.map((p) => p.category).toSet();
    return PackageCategory.values.where(present.contains).toList();
  }

  /// Packages after applying search + category + status filters.
  List<SdkPackage> get filtered {
    final q = query.trim().toLowerCase();
    return packages.where((p) {
      if (category != null && p.category != category) return false;
      if (updatesOnly && !p.hasUpdate) return false;
      if (installedOnly && !p.isInstalled) return false;
      if (q.isNotEmpty &&
          !p.path.toLowerCase().contains(q) &&
          !p.description.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  SdkManagerState copyWith({
    SdkManagerStatus? status,
    List<SdkPackage>? packages,
    String? query,
    PackageCategory? category,
    bool? updatesOnly,
    bool? installedOnly,
    String? errorMessage,
    bool clearError = false,
    bool clearCategory = false,
  }) {
    return SdkManagerState(
      status: status ?? this.status,
      packages: packages ?? this.packages,
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      updatesOnly: updatesOnly ?? this.updatesOnly,
      installedOnly: installedOnly ?? this.installedOnly,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        packages,
        query,
        category,
        updatesOnly,
        installedOnly,
        errorMessage,
      ];
}
