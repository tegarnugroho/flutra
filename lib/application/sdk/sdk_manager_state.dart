part of 'sdk_manager_cubit.dart';

enum SdkManagerStatus { initial, loading, ready, failure }

/// Column the package list is sorted by.
enum PackageSort { name, status, version }

extension PackageSortLabel on PackageSort {
  String get label => switch (this) {
        PackageSort.name => 'Name',
        PackageSort.status => 'Status',
        PackageSort.version => 'Version',
      };
}

/// Immutable state for the Package Manager: catalogue, filters, selection,
/// install queue and streamed console output.
class SdkManagerState extends Equatable {
  const SdkManagerState({
    this.status = SdkManagerStatus.initial,
    this.packages = const [],
    this.query = '',
    this.category,
    this.updatesOnly = false,
    this.installedOnly = false,
    this.sort = PackageSort.name,
    this.selected = const {},
    this.selectedPath,
    this.queue = const [],
    this.activePath,
    this.progress,
    this.console = const [],
    this.consoleVisible = false,
    this.busy = false,
    this.errorMessage,
  });

  final SdkManagerStatus status;
  final List<SdkPackage> packages;
  final String query;
  final PackageCategory? category;
  final bool updatesOnly;
  final bool installedOnly;
  final PackageSort sort;

  /// Paths ticked for bulk operations.
  final Set<String> selected;

  /// Path shown in the details panel.
  final String? selectedPath;

  /// Paths waiting to be installed (excludes the active one).
  final List<String> queue;

  /// Package currently installing/uninstalling, with its [progress] 0–1.
  final String? activePath;
  final double? progress;

  /// Streamed sdkmanager output lines (bounded).
  final List<String> console;
  final bool consoleVisible;

  /// True while any install/uninstall/update operation is running.
  final bool busy;

  final String? errorMessage;

  bool get isLoading => status == SdkManagerStatus.loading;
  int get updateCount => packages.where((p) => p.hasUpdate).length;
  int get installedCount => packages.where((p) => p.isInstalled).length;
  int get queuedCount => queue.length + (activePath != null ? 1 : 0);

  SdkPackage? get selectedPackage {
    for (final p in packages) {
      if (p.path == selectedPath) return p;
    }
    return null;
  }

  /// Count of packages per category (for sidebar badges).
  Map<PackageCategory, int> get categoryCounts {
    final counts = <PackageCategory, int>{};
    for (final p in packages) {
      counts.update(p.category, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  List<PackageCategory> get availableCategories {
    final present = packages.map((p) => p.category).toSet();
    return PackageCategory.values.where(present.contains).toList();
  }

  /// Packages after search + category + status filters, then sorted.
  List<SdkPackage> get filtered {
    final q = query.trim().toLowerCase();
    final list = packages.where((p) {
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

    int byKey(SdkPackage a, SdkPackage b) => switch (sort) {
          PackageSort.name => a.description
              .toLowerCase()
              .compareTo(b.description.toLowerCase()),
          PackageSort.status => a.state.index.compareTo(b.state.index),
          PackageSort.version =>
            (b.displayVersion ?? '').compareTo(a.displayVersion ?? ''),
        };
    list.sort((a, b) {
      final byCat = a.category.index.compareTo(b.category.index);
      return byCat != 0 ? byCat : byKey(a, b);
    });
    return list;
  }

  bool isQueued(String path) => queue.contains(path);
  bool isActive(String path) => activePath == path;

  SdkManagerState copyWith({
    SdkManagerStatus? status,
    List<SdkPackage>? packages,
    String? query,
    PackageCategory? category,
    bool? updatesOnly,
    bool? installedOnly,
    PackageSort? sort,
    Set<String>? selected,
    String? selectedPath,
    List<String>? queue,
    String? activePath,
    double? progress,
    List<String>? console,
    bool? consoleVisible,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
    bool clearCategory = false,
    bool clearActive = false,
    bool clearSelectedPath = false,
  }) {
    return SdkManagerState(
      status: status ?? this.status,
      packages: packages ?? this.packages,
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      updatesOnly: updatesOnly ?? this.updatesOnly,
      installedOnly: installedOnly ?? this.installedOnly,
      sort: sort ?? this.sort,
      selected: selected ?? this.selected,
      selectedPath:
          clearSelectedPath ? null : (selectedPath ?? this.selectedPath),
      queue: queue ?? this.queue,
      activePath: clearActive ? null : (activePath ?? this.activePath),
      progress: clearActive ? null : (progress ?? this.progress),
      console: console ?? this.console,
      consoleVisible: consoleVisible ?? this.consoleVisible,
      busy: busy ?? this.busy,
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
        sort,
        selected,
        selectedPath,
        queue,
        activePath,
        progress,
        console,
        consoleVisible,
        busy,
        errorMessage,
      ];
}
