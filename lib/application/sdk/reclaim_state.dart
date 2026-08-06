part of 'reclaim_cubit.dart';

/// Which step of the dialog is on screen.
enum ReclaimPhase { scanning, review, confirm, removing, finished }

/// Immutable state of the reclaimable-storage flow.
class ReclaimState extends Equatable {
  const ReclaimState({
    this.phase = ReclaimPhase.scanning,
    this.report,
    this.selected = const {},
    this.statuses = const {},
    this.lines = const [],
    this.currentItemId,
    this.freedBytes = 0,
    this.errorMessage,
  });

  final ReclaimPhase phase;

  /// Null until the first scan lands.
  final ReclaimableReport? report;

  /// Ids the user has ticked.
  final Set<String> selected;

  /// Per-item outcome during and after a run.
  final Map<String, ReclaimItemStatus> statuses;

  /// sdkmanager output for the run.
  final List<CommandOutputLine> lines;

  /// The item being worked on right now.
  final String? currentItemId;

  /// Sum of what actually went, for the closing summary.
  final int freedBytes;

  final String? errorMessage;

  bool get isScanning => phase == ReclaimPhase.scanning;
  bool get isRemoving => phase == ReclaimPhase.removing;
  bool get isFinished => phase == ReclaimPhase.finished;

  List<ReclaimableItem> get items => report?.items ?? const [];

  /// The ticked items, in list order.
  List<ReclaimableItem> get selectedItems =>
      items.where((i) => selected.contains(i.id) && !i.isBlocked).toList();

  /// What the selection is expected to free. Items still being measured count
  /// as nothing rather than as a guess.
  int get selectedBytes =>
      selectedItems.fold(0, (sum, i) => sum + (i.sizeBytes ?? 0));

  bool get hasFailures =>
      statuses.values.any((s) => s == ReclaimItemStatus.failed);

  /// The items a finished run could not remove, for the retry action.
  List<ReclaimableItem> get failedItems => [
        for (final item in items)
          if (statuses[item.id] == ReclaimItemStatus.failed) item,
      ];

  ReclaimState copyWith({
    ReclaimPhase? phase,
    ReclaimableReport? report,
    Set<String>? selected,
    Map<String, ReclaimItemStatus>? statuses,
    List<CommandOutputLine>? lines,
    String? currentItemId,
    int? freedBytes,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReclaimState(
      phase: phase ?? this.phase,
      report: report ?? this.report,
      selected: selected ?? this.selected,
      statuses: statuses ?? this.statuses,
      lines: lines ?? this.lines,
      currentItemId: currentItemId ?? this.currentItemId,
      freedBytes: freedBytes ?? this.freedBytes,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        phase,
        report,
        selected,
        statuses,
        lines,
        currentItemId,
        freedBytes,
        errorMessage,
      ];
}
