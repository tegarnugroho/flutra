import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/storage_report.dart';
import '../../common/app_loader.dart';
import '../../common/grouped_list.dart';
import '../../common/skeleton/skeleton_primitives.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Human size, one decimal past a gigabyte.
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).round()} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// "2 hours ago" — precise enough for "is this stale?", no more.
String formatAge(DateTime when) {
  final age = DateTime.now().difference(when);
  if (age.inMinutes < 1) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) {
    return '${age.inHours} hour${age.inHours == 1 ? '' : 's'} ago';
  }
  return '${age.inDays} day${age.inDays == 1 ? '' : 's'} ago';
}

/// Where the toolchain's disk goes, and what looks reclaimable.
class StoragePanel extends StatefulWidget {
  const StoragePanel({
    super.key,
    required this.report,
    required this.scanning,
    required this.onAnalyze,
    required this.onReview,
  });

  final StorageReport? report;
  final bool scanning;
  final VoidCallback onAnalyze;

  /// Routes a finding to the screen that owns its cleanup. The dashboard never
  /// deletes anything itself.
  final void Function(ReclaimableFinding) onReview;

  @override
  State<StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<StoragePanel> {
  StorageCategory? _expanded;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final report = widget.report;
    final slices = report?.sorted ?? const <StorageSlice>[];

    return GroupedBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Storage analysis', style: text.rowTitle),
              const SizedBox(width: 10),
              if (report != null && !widget.scanning)
                Text('Analyzed ${formatAge(report.scannedAt)}',
                    style: text.caption),
              const Spacer(),
              if (widget.scanning)
                Row(
                  children: [
                    const AppLoader(size: AppLoaderSize.small),
                    const SizedBox(width: 8),
                    Text('Analyzing…', style: text.caption),
                  ],
                )
              else
                _TextAction(label: 'Analyze again', onTap: widget.onAnalyze),
            ],
          ),
          const SizedBox(height: 12),
          if (report == null && widget.scanning)
            // The bar and legend that are being measured, in their own shapes.
            // A sentence alone read as an idle panel that then produced
            // numbers out of nowhere.
            const StorageFiguresSkeleton()
          else if (report == null)
            Text(
              'No scan yet — run one to see where the disk goes.',
              style: text.caption,
            )
          else ...[
            _StackedBar(slices: slices, total: report.totalBytes),
            const SizedBox(height: 14),
            _Legend(
              slices: slices,
              total: report.totalBytes,
              expanded: _expanded,
              onToggle: (category) => setState(
                () => _expanded = _expanded == category ? null : category,
              ),
            ),
            if (report.skipped.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Not measured: '
                '${report.skipped.map((c) => c.label).join(', ')} '
                '— path not set or unreadable',
                style: text.caption,
              ),
            ],
            if (report.findings.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ReclaimBanner(
                findings: report.findings,
                onReview: widget.onReview,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Stands in for the bar and legend while the disk walk is still running.
///
/// Shaped like the real thing so nothing jumps when the figures land, and
/// shimmering so the panel reads as working rather than empty. Public because
/// the dashboard skeleton stands in for this very panel and must not draw a
/// second, drifting copy of it.
class StorageFiguresSkeleton extends StatelessWidget {
  const StorageFiguresSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 10, radius: 5),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < 2; column++) ...[
                if (column > 0) const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      for (var row = 0; row < 2; row++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const SkeletonBox(width: 9, height: 9, radius: 2),
                              const SizedBox(width: 8),
                              SkeletonLine(
                                width: 84 + (column * 18) + (row * 12),
                                height: 11,
                              ),
                              const Spacer(),
                              const SkeletonLine(width: 48, height: 11),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One rounded bar, a segment per category.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.slices, required this.total});

  final List<StorageSlice> slices;
  final int total;

  /// Anything under this share is folded into the tail — a 3px sliver reads as
  /// a rendering artefact, not as data.
  static const double _mergeBelow = 0.02;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (total <= 0) return const SizedBox.shrink();

    final visible = <(StorageSlice, int)>[];
    var mergedBytes = 0;
    for (var i = 0; i < slices.length; i++) {
      if (slices[i].bytes / total < _mergeBelow) {
        mergedBytes += slices[i].bytes;
      } else {
        visible.add((slices[i], i));
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final (slice, index) in visible)
              Expanded(
                flex: slice.bytes,
                child: Tooltip(
                  message:
                      '${slice.category.label} · ${formatBytes(slice.bytes)} · '
                      '${(slice.bytes / total * 100).round()}%',
                  child: ColoredBox(
                    color: AppColors.chart(palette.brightness, index),
                  ),
                ),
              ),
            if (mergedBytes > 0)
              Expanded(
                flex: mergedBytes,
                child: Tooltip(
                  message: 'Other · ${formatBytes(mergedBytes)}',
                  child: ColoredBox(color: palette.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Two columns of colour dot + name + size; a row opens its largest items.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.slices,
    required this.total,
    required this.expanded,
    required this.onToggle,
  });

  final List<StorageSlice> slices;
  final int total;
  final StorageCategory? expanded;
  final ValueChanged<StorageCategory> onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 420 ? 1 : 2;
        return Column(
          children: [
            for (var row = 0; row * columns < slices.length; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (var col = 0; col < columns; col++)
                      Expanded(
                        child: row * columns + col < slices.length
                            ? _LegendRow(
                                slice: slices[row * columns + col],
                                index: row * columns + col,
                                onTap: () => onToggle(
                                  slices[row * columns + col].category,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            if (expanded != null)
              _EntryList(
                slice: slices.firstWhere((s) => s.category == expanded),
              ),
          ],
        );
      },
    );
  }
}

class _LegendRow extends StatefulWidget {
  const _LegendRow({
    required this.slice,
    required this.index,
    required this.onTap,
  });

  final StorageSlice slice;
  final int index;
  final VoidCallback onTap;

  @override
  State<_LegendRow> createState() => _LegendRowState();
}

class _LegendRowState extends State<_LegendRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: AppColors.chart(palette.brightness, widget.index),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.slice.category.label,
                  style: _hovered
                      ? text.rowLabel.copyWith(color: palette.textPrimary)
                      : text.rowLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(formatBytes(widget.slice.bytes), style: text.monoValue),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.slice});

  final StorageSlice slice;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    if (slice.entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Nothing itemised here.', style: text.caption),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.logBg,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Column(
        children: [
          for (final entry in slice.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.name,
                      style: text.monoPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(formatBytes(entry.bytes), style: text.monoValue),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Summarises up to two findings and routes the rest to the owning screen.
class _ReclaimBanner extends StatelessWidget {
  const _ReclaimBanner({required this.findings, required this.onReview});

  final List<ReclaimableFinding> findings;
  final void Function(ReclaimableFinding) onReview;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final total = findings.fold(0, (sum, f) => sum + f.bytes);
    final headline = findings
        .take(2)
        .map((f) => '${f.summary} (~${formatBytes(f.bytes)})')
        .join(' · ');
    final rest = findings.length - 2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.dangerSurface,
        border: Border.all(color: palette.statusWarn, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rest > 0
                  ? '$headline · and $rest more — '
                        '~${formatBytes(total)} reclaimable'
                  : '$headline — ~${formatBytes(total)} reclaimable',
              style: text.statusLine.copyWith(color: palette.statusWarn),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          _TextAction(
            label: 'Review',
            color: palette.statusWarn,
            onTap: () => onReview(findings.first),
          ),
        ],
      ),
    );
  }
}

class _TextAction extends StatefulWidget {
  const _TextAction({required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final color = widget.color ?? palette.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: text.rowLabel.copyWith(
            color: color,
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}
