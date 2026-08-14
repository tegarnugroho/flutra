part of 'sdk_manager_cubit.dart';

enum SdkManagerStatus { initial, loading, ready, failure }

/// Why the package list is empty — which is what decides whether this page shows
/// a way forward or a dead end.
///
/// The page used to have one failure: "could not query the SDK", with a Retry
/// button. On a machine with no SDK at all that was a dead end, because the only
/// thing that could have fixed it — installing `cmdline-tools` — needs the
/// `sdkmanager` that lives inside `cmdline-tools`. Telling the three cases apart
/// is what lets each one offer the action that actually applies.
enum SdkAvailability {
  /// Nothing is wrong, or nothing has been established yet.
  ok,

  /// No SDK root found anywhere and no sdkmanager. Nothing to repair — an SDK
  /// has to be created, or an existing one pointed at.
  noSdk,

  /// An SDK root exists but has no command-line tools in it. Half an install,
  /// usually an Android Studio SDK someone stripped, and the repair is narrow.
  sdkFoundNoCmdlineTools,

  /// sdkmanager is present and ran, and the run failed. The only case where
  /// Retry is the honest offer.
  queryFailed;

  bool get isBootstrappable =>
      this == SdkAvailability.noSdk ||
      this == SdkAvailability.sdkFoundNoCmdlineTools;
}

/// Which of [SdkAvailability]'s cases a failed query landed in.
///
/// Pure, because the branch decides which UI the user sees and "what happens on
/// a machine with a half-installed SDK" should be answerable without one.
SdkAvailability classifySdkFailure({
  required bool hasSdkRoot,
  required bool hasSdkManager,
}) {
  if (hasSdkManager) return SdkAvailability.queryFailed;
  return hasSdkRoot
      ? SdkAvailability.sdkFoundNoCmdlineTools
      : SdkAvailability.noSdk;
}

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
    this.errorDetail,
    this.availability = SdkAvailability.ok,
    this.bootstrap,
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

  /// The tool's own output behind a failure — stderr, an exit code — kept out of
  /// [errorMessage] so the page can put it behind a disclosure instead of
  /// leading with a stack of sdkmanager noise.
  final String? errorDetail;

  /// Which failure this is, and so which way out the page offers.
  final SdkAvailability availability;

  /// The first-run bootstrap, while it runs. Null when none is in flight.
  final SdkBootstrapEvent? bootstrap;

  bool get isLoading => status == SdkManagerStatus.loading;

  /// True while the SDK is being created from nothing.
  bool get isBootstrapping =>
      bootstrap != null &&
      bootstrap!.stage != SdkBootstrapStage.done &&
      bootstrap!.stage != SdkBootstrapStage.failed;

  /// True when the bootstrap is stopped waiting for the licences to be accepted.
  bool get awaitingLicences =>
      bootstrap?.stage == SdkBootstrapStage.awaitingLicences;

  /// True until the first load settles, so a screen with no data yet shows its
  /// skeleton from the very first frame.
  ///
  /// `isLoading` alone is not enough: the cubit is created during the first
  /// build and its status is still `initial` while that frame renders, which
  /// would flash the centred empty state before the skeleton takes over.
  bool get isFirstLoad =>
      packages.isEmpty &&
      (status == SdkManagerStatus.initial ||
          status == SdkManagerStatus.loading);
  int get updateCount => packages.where((p) => p.hasUpdate).length;
  int get installedCount => packages.where((p) => p.isInstalled).length;

  /// Checked packages that can be installed or updated.
  int get installableSelectedCount => packages
      .where((p) =>
          selected.contains(p.path) && (!p.isInstalled || p.hasUpdate))
      .length;

  /// Checked packages that are installed (so removable).
  int get removableSelectedCount => packages
      .where((p) => selected.contains(p.path) && p.isInstalled)
      .length;
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

  /// Whether anything the user chose is narrowing the list.
  ///
  /// What makes an empty list empty decides what the page is allowed to say
  /// about it: "adjust the search or filters" is only true when there are
  /// filters to adjust, and it read as a lie on the screen this was written
  /// for — a fresh SDK whose catalogue had failed to load showed zero packages
  /// and blamed a search box the user had never typed in.
  bool get hasActiveFilters =>
      query.trim().isNotEmpty || category != null || updatesOnly || installedOnly;

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
    String? errorDetail,
    SdkAvailability? availability,
    SdkBootstrapEvent? bootstrap,
    bool clearBootstrap = false,
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
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
      availability: availability ?? this.availability,
      bootstrap: clearBootstrap ? null : (bootstrap ?? this.bootstrap),
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
        errorDetail,
        availability,
        bootstrap,
      ];
}
