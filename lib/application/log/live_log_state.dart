part of 'live_log_cubit.dart';

enum LiveLogStatus { idle, starting, running, stopped, failure }

/// Immutable state for a live log stream, including filters.
class LiveLogState extends Equatable {
  const LiveLogState({
    this.status = LiveLogStatus.idle,
    this.lines = const [],
    this.paused = false,
    this.query = '',
    this.useRegex = false,
    this.tagFilter = '',
    this.minPriority = LogPriority.verbose,
    this.errorMessage,
  });

  final LiveLogStatus status;
  final List<LogLine> lines;
  final bool paused;
  final String query;
  final bool useRegex;
  final String tagFilter;
  final LogPriority minPriority;
  final String? errorMessage;

  bool get isRunning => status == LiveLogStatus.running;
  bool get isStarting => status == LiveLogStatus.starting;

  /// Lines after applying priority, tag and text/regex filters.
  List<LogLine> get filtered {
    final q = query.trim();
    final tag = tagFilter.trim().toLowerCase();
    RegExp? re;
    if (useRegex && q.isNotEmpty) {
      try {
        re = RegExp(q, caseSensitive: false);
      } catch (_) {
        re = null; // invalid regex → treat as no text filter
      }
    }
    return lines.where((l) {
      if (l.priority.rank < minPriority.rank &&
          l.priority != LogPriority.unknown) {
        return false;
      }
      if (tag.isNotEmpty && !(l.tag?.toLowerCase().contains(tag) ?? false)) {
        return false;
      }
      if (q.isEmpty) return true;
      if (re != null) return re.hasMatch(l.raw);
      return l.raw.toLowerCase().contains(q.toLowerCase());
    }).toList();
  }

  LiveLogState copyWith({
    LiveLogStatus? status,
    List<LogLine>? lines,
    bool? paused,
    String? query,
    bool? useRegex,
    String? tagFilter,
    LogPriority? minPriority,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LiveLogState(
      status: status ?? this.status,
      lines: lines ?? this.lines,
      paused: paused ?? this.paused,
      query: query ?? this.query,
      useRegex: useRegex ?? this.useRegex,
      tagFilter: tagFilter ?? this.tagFilter,
      minPriority: minPriority ?? this.minPriority,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        lines,
        paused,
        query,
        useRegex,
        tagFilter,
        minPriority,
        errorMessage,
      ];
}
