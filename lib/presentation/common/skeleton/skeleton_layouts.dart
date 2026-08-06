import 'package:fluent_ui/fluent_ui.dart';

import '../../dashboard/widgets/stat_cards.dart';
import '../../dashboard/widgets/storage_panel.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../grouped_list.dart';
import '../page_scaffold.dart';
import '../tile_box.dart';
import 'skeleton_primitives.dart';

/// The frame every screen skeleton shares: page-body padding, one shimmer
/// controller for the whole subtree, and a left-aligned column.
///
/// Sizes here mirror the real rows on purpose — [GroupedListRow] pads 12/9 and
/// its title line is 12.5px, so a 36px row with a 12px line lands the content
/// where it will actually appear and nothing jumps on the swap.
class _SkeletonPage extends StatelessWidget {
  const _SkeletonPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Padding(
        padding: kPageBodyPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// A skeleton standing in for a [SectionLabel].
class _SectionLabelSkeleton extends StatelessWidget {
  const _SectionLabelSkeleton({this.width = 80});

  final double width;

  @override
  Widget build(BuildContext context) => SkeletonLine(width: width, height: 11);
}

/// A skeleton standing in for a [StatusLine] — dot plus one line.
class _StatusLineSkeleton extends StatelessWidget {
  const _StatusLineSkeleton({this.width = 280});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SkeletonCircle(size: 7),
        const SizedBox(width: 8),
        SkeletonLine(width: width, height: 12),
      ],
    );
  }
}

/// One row inside a skeleton [GroupedList], padded like [GroupedListRow].
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.children, this.height = 18});

  final List<Widget> children;

  /// Height of the row's content band, excluding the 9px vertical padding.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: SizedBox(
        height: height,
        child: Row(children: children),
      ),
    );
  }
}

/// A skeleton [GroupedList]: same hairline box and dividers as the real one.
class _SkeletonGroup extends StatelessWidget {
  const _SkeletonGroup({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => GroupedList(children: rows);
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

/// The dashboard, with everything that is known already drawn for real.
///
/// Only the parts still being fetched shimmer — the numbers, the tool names
/// and versions, the storage figures. Card borders, the section label and the
/// stat labels are not waiting on anything, so turning them into grey slabs
/// only made the page look emptier than it is.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    return _SkeletonPage(
      children: [
        const _StatusLineSkeleton(width: 300),
        const SizedBox(height: 14),
        const StatCardsSkeleton(),
        const SizedBox(height: 14),
        const SectionLabel('Toolchain'),
        const SizedBox(height: 8),
        _SkeletonGroup(
          rows: [
            for (final width in const [92.0, 118.0, 74.0, 104.0, 86.0])
              _SkeletonRow(
                children: [
                  const SkeletonCircle(size: 16),
                  const SizedBox(width: 10),
                  SkeletonLine(width: width, height: 12),
                  const Spacer(),
                  const SkeletonLine(width: 60, height: 11),
                  const SizedBox(width: 10),
                  const SkeletonCircle(size: 6),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        // Storage panel: real box and title, shimmering figures.
        GroupedBox(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Storage analysis', style: text.rowTitle),
                  const SizedBox(width: 10),
                  const SkeletonLine(width: 96, height: 10),
                ],
              ),
              const SizedBox(height: 12),
              // The same placeholder the panel itself shows while scanning, so
              // the hand-over from skeleton to panel changes nothing on screen.
              const StorageFiguresSkeleton(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Quick actions: real frames, shimmering icon and labels.
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: StatCardShell(
                  child: SizedBox(
                    height: kQuickActionHeight - 20,
                    child: Row(
                      children: [
                        const SkeletonCircle(size: 18),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonLine(width: 104 + i * 14, height: 12),
                            const SizedBox(height: 6),
                            SkeletonLine(width: 72 + i * 8, height: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SDK manager
// ---------------------------------------------------------------------------

/// Toolbar band, category rail and the package rows.
class SdkManagerSkeleton extends StatelessWidget {
  const SdkManagerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SkeletonShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toolbar: search field plus a few filter controls.
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                SkeletonBox(width: 220, height: 30),
                SizedBox(width: 8),
                SkeletonBox(width: 120, height: 30),
                SizedBox(width: 8),
                SkeletonBox(width: 96, height: 30),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 180,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final width in const [96.0, 118.0, 82.0, 104.0])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: SkeletonLine(width: width, height: 12),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(width: AppShape.hairline, color: palette.border),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: _SkeletonGroup(
                      rows: [
                        for (var i = 0; i < 8; i++)
                          _SkeletonRow(
                            children: [
                              const SkeletonBox(
                                width: 16,
                                height: 16,
                                radius: 3,
                              ),
                              const SizedBox(width: 10),
                              SkeletonLine(
                                width: 160 + (i % 4) * 34,
                                height: 12,
                              ),
                              const Spacer(),
                              const SkeletonLine(width: 54, height: 11),
                              const SizedBox(width: 12),
                              const SkeletonBox(width: 64, height: 18),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Virtual devices
// ---------------------------------------------------------------------------

/// Three AVD rows: name plus inline detail, with trailing actions.
class EmulatorListSkeleton extends StatelessWidget {
  const EmulatorListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _SkeletonPage(
      children: [
        for (final width in const [148.0, 190.0, 122.0])
          Padding(
            padding: const EdgeInsets.only(bottom: TileBox.gap),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: palette.border,
                  width: AppShape.hairline,
                ),
                borderRadius: BorderRadius.circular(TileBox.radius),
              ),
              child: Row(
                children: [
                  const SkeletonBox(width: 32, height: 32),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: width, height: 13),
                      const SizedBox(height: 5),
                      SkeletonLine(width: width + 110, height: 11),
                    ],
                  ),
                  const Spacer(),
                  const SkeletonBox(width: 64, height: 22),
                  const SizedBox(width: 6),
                  const SkeletonBox(width: 30, height: 22),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------------

/// Three connected-device rows: title over a second meta line, trailing pill.
class DeviceListSkeleton extends StatelessWidget {
  const DeviceListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SkeletonPage(
      children: [
        const _SectionLabelSkeleton(width: 86),
        const SizedBox(height: 8),
        _SkeletonGroup(
          rows: [
            for (final width in const [132.0, 168.0, 110.0])
              _SkeletonRow(
                height: 30,
                children: [
                  const SkeletonCircle(size: 6),
                  const SizedBox(width: 10),
                  const SkeletonCircle(size: 16),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: width, height: 12),
                      const SizedBox(height: 5),
                      SkeletonLine(width: width * 0.7, height: 10),
                    ],
                  ),
                  const Spacer(),
                  const SkeletonBox(width: 62, height: 20),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Updates
// ---------------------------------------------------------------------------

/// Status line plus four update rows with a trailing action.
class UpdatesSkeleton extends StatelessWidget {
  const UpdatesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SkeletonPage(
      children: [
        const _StatusLineSkeleton(width: 260),
        const SizedBox(height: 18),
        const _SectionLabelSkeleton(width: 92),
        const SizedBox(height: 8),
        _SkeletonGroup(
          rows: [
            for (final width in const [186.0, 148.0, 214.0, 160.0])
              _SkeletonRow(
                children: [
                  const SkeletonCircle(size: 6),
                  const SizedBox(width: 10),
                  SkeletonLine(width: width, height: 12),
                  const Spacer(),
                  const SkeletonLine(width: 76, height: 11),
                  const SizedBox(width: 12),
                  const SkeletonBox(width: 72, height: 20),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Flutter SDK
// ---------------------------------------------------------------------------

/// The identity panel, the channel row, then the version tiles.
///
/// Mirrors the real page's shape rather than the old card-and-group one: the
/// tiles are separate boxes with a gap, so a skeleton drawn as one group would
/// resolve into a different layout the moment data arrives.
class FlutterSdkSkeleton extends StatelessWidget {
  const FlutterSdkSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _SkeletonPage(
      children: [
        GroupedBox(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 40, height: 40, radius: 8),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: 132, height: 20),
                    SizedBox(height: 12),
                    SkeletonLine(width: 320, height: 12),
                  ],
                ),
              ),
              SizedBox(width: 16),
              SkeletonBox(width: 118, height: 26),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Row(
          children: [
            SkeletonBox(width: 190, height: 30),
            Spacer(),
            SkeletonLine(width: 70, height: 11),
            SizedBox(width: 10),
            SkeletonBox(width: 200, height: 30),
          ],
        ),
        const SizedBox(height: 16),
        for (final width in const [96.0, 112.0, 88.0, 104.0])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: palette.border,
                  width: AppShape.hairline,
                ),
                borderRadius: BorderRadius.circular(TileBox.radius),
              ),
              child: Row(
                children: [
                  const SkeletonBox(width: 8, height: 8, radius: 4),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: width, height: 13),
                      const SizedBox(height: 5),
                      SkeletonLine(width: width + 96, height: 11),
                    ],
                  ),
                  const Spacer(),
                  const SkeletonBox(width: 12, height: 12, radius: 3),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Flutter doctor
// ---------------------------------------------------------------------------

/// Status line, progress bar and six pending check rows.
///
/// Only shown between "run started" and the first check arriving — once checks
/// stream in, the real rows take over and show their own per-check state.
class DoctorSkeleton extends StatelessWidget {
  const DoctorSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SkeletonPage(
      children: [
        const _StatusLineSkeleton(width: 220),
        const SizedBox(height: 8),
        const SkeletonBox(height: 4, radius: 2),
        const SizedBox(height: 14),
        const _SectionLabelSkeleton(width: 52),
        const SizedBox(height: 8),
        _SkeletonGroup(
          rows: [
            for (final width in const [
              206.0,
              158.0,
              244.0,
              180.0,
              132.0,
              198.0,
            ])
              _SkeletonRow(
                children: [
                  const SkeletonCircle(size: 16),
                  const SizedBox(width: 10),
                  SkeletonLine(width: width, height: 12),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Logcat
// ---------------------------------------------------------------------------

/// Device picker and toolbar, then a block of log lines.
class LogcatSkeleton extends StatelessWidget {
  const LogcatSkeleton({super.key});

  /// Line widths as a fraction of the log pane, 60–95% like real log output.
  static const _lineFractions = <double>[
    0.82,
    0.61,
    0.94,
    0.70,
    0.88,
    0.66,
    0.91,
    0.75,
    0.63,
    0.86,
    0.72,
    0.95,
  ];

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                SkeletonBox(width: 240, height: 30),
                SizedBox(width: 8),
                SkeletonBox(width: 130, height: 30),
                SizedBox(width: 8),
                SkeletonBox(width: 90, height: 30),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _StatusLineSkeleton(width: 200),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GroupedBox(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final fraction in _lineFractions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: SkeletonLine(
                            width: constraints.maxWidth * fraction,
                            height: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
