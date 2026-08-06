import 'package:fluent_ui/fluent_ui.dart';

import '../../../application/emulator/emulator_list_cubit.dart';
import '../../../domain/entities/avd.dart';
import '../../common/outlined_action_button.dart';
import '../../common/status_pill.dart';
import '../../common/tile_box.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// One virtual device: what it is, whether it is running, and the one action
/// worth a button.
///
/// Start is on the tile rather than behind the kebab because starting a device
/// is what this page is for; everything else is a menu item.
class AvdTile extends StatefulWidget {
  const AvdTile({
    super.key,
    required this.avd,
    required this.task,
    required this.onStart,
    required this.onColdBoot,
    required this.onStop,
    required this.onWipe,
    required this.onDelete,
    required this.onDuplicate,
    required this.onConsole,
    required this.onShowInFolder,
  });

  final Avd avd;

  /// The operation in flight for this device, or null when it is idle.
  final AvdTask? task;

  final VoidCallback onStart;
  final VoidCallback onColdBoot;
  final VoidCallback onStop;
  final VoidCallback onWipe;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onConsole;

  /// Null when the AVD reports no directory to open.
  final VoidCallback? onShowInFolder;

  @override
  State<AvdTile> createState() => _AvdTileState();
}

class _AvdTileState extends State<AvdTile> {
  final _menu = FlyoutController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  bool get _busy => widget.task != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final avd = widget.avd;

    return TileBox(
      emphasised: avd.isRunning,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _DeviceMark(kind: avd.kind, running: avd.isRunning),
            const SizedBox(width: 12),
            Expanded(child: _identity(context, palette)),
            const SizedBox(width: 12),
            _runButton(palette),
            const SizedBox(width: 6),
            FlyoutTarget(
              controller: _menu,
              child: OutlinedActionButton(
                icon: FluentIcons.more,
                dense: true,
                tooltip: 'More actions',
                onPressed: () => _showMenu(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identity(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    final avd = widget.avd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                avd.name,
                style: text.rowTitle.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // A device mid-transition is neither running nor stopped, so it
            // gets the pulse rather than a pill that would have to lie.
            if (widget.task != null) ...[
              const SizedBox(width: 8),
              _PulsingDot(color: palette.textMuted),
            ] else if (avd.isRunning) ...[
              const SizedBox(width: 8),
              StatusPill(
                label: 'running',
                foreground: palette.statusOk,
                background: palette.okSurface,
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        _MetaLine(avd: avd),
      ],
    );
  }

  Widget _runButton(AppPalette palette) {
    final task = widget.task;
    if (task != null) {
      return OutlinedActionButton(
        icon: FluentIcons.play_solid,
        label: task.label,
        dense: true,
        busy: true,
        // Disabled: the emulator is mid-transition and a second command would
        // race the first.
        onPressed: null,
      );
    }
    if (widget.avd.isRunning) {
      return OutlinedActionButton(
        icon: FluentIcons.stop,
        label: 'Stop',
        dense: true,
        // Quiet at rest, red under the pointer — stopping is recoverable, so
        // it warns on approach rather than shouting from the list.
        dangerOnHover: true,
        onPressed: widget.onStop,
      );
    }
    return OutlinedActionButton(
      icon: FluentIcons.play_solid,
      label: 'Start',
      dense: true,
      onPressed: widget.onStart,
    );
  }

  void _showMenu(BuildContext context) {
    final palette = AppPalette.of(context);
    final avd = widget.avd;
    _menu.showFlyout(
      builder: (flyoutContext) {
        void run(VoidCallback action) {
          Navigator.of(flyoutContext).pop();
          action();
        }

        return MenuFlyout(
          items: [
            // Run variants: what else there is to do with a device that is
            // stopped, or a way into one that is already up.
            if (avd.isRunning)
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.command_prompt, size: 14),
                text: const Text('Emulator console'),
                onPressed: () => run(widget.onConsole),
              )
            else
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.a_a_d_logo, size: 14),
                text: const Text('Cold boot'),
                onPressed: _busy ? null : () => run(widget.onColdBoot),
              ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.copy, size: 14),
              text: const Text('Duplicate'),
              onPressed: _busy ? null : () => run(widget.onDuplicate),
            ),
            if (widget.onShowInFolder != null)
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.folder_open, size: 14),
                text: const Text('Show in folder'),
                onPressed: () => run(widget.onShowInFolder!),
              ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: Icon(
                FluentIcons.clear_selection,
                size: 14,
                color: avd.isRunning || _busy ? null : palette.statusError,
              ),
              text: Text(
                'Wipe data',
                style: avd.isRunning || _busy
                    ? null
                    : TextStyle(color: palette.statusError),
              ),
              onPressed: avd.isRunning || _busy
                  ? null
                  : () => run(widget.onWipe),
            ),
            MenuFlyoutItem(
              leading: Icon(
                FluentIcons.delete,
                size: 14,
                color: avd.isRunning || _busy ? null : palette.statusError,
              ),
              text: Tooltip(
                message: avd.isRunning ? 'Stop the device first' : '',
                child: Text(
                  'Delete',
                  style: avd.isRunning || _busy
                      ? null
                      : TextStyle(color: palette.statusError),
                ),
              ),
              onPressed: avd.isRunning || _busy
                  ? null
                  : () => run(widget.onDelete),
            ),
          ],
        );
      },
    );
  }
}

/// A dot that breathes while an operation is in flight.
///
/// The button already says what is happening; this is the ambient half of it,
/// so a list scanned from the left still shows which device is busy.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Same rule the loader and the skeletons follow: no ticker at all when the
    // OS asks for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: SizedBox(
        width: 6,
        height: 6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// The device-family icon in its rounded square.
class _DeviceMark extends StatelessWidget {
  const _DeviceMark({required this.kind, required this.running});

  final AvdDeviceKind kind;
  final bool running;

  static IconData iconFor(AvdDeviceKind kind) => switch (kind) {
    AvdDeviceKind.phone => FluentIcons.cell_phone,
    AvdDeviceKind.tablet => FluentIcons.tablet,
    AvdDeviceKind.tv => FluentIcons.t_v_monitor,
    AvdDeviceKind.wear => FluentIcons.circle_ring,
  };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: running ? palette.okSurface : palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Icon(
        iconFor(kind),
        size: 15,
        color: running ? palette.statusOk : palette.textSecondary,
      ),
    );
  }
}

/// `Pixel 6 · Android 14 (API 34) · Play Store · x86_64`.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.avd});

  final Avd avd;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    final mono = text.monoMeta.copyWith(fontSize: 11);
    final profile = avd.deviceName ?? avd.deviceId;
    final platform = _platform(avd);
    final image = avd.displayImageType;

    return Row(
      children: [
        // Every segment is flexible so a narrow window ellipsizes them rather
        // than overflowing the tile; the short ones never claim the room.
        if (profile != null) ...[
          Flexible(child: _text(profile, text.caption)),
          if (platform != null || image != null || avd.abi != null)
            _Separator(style: text.caption),
        ],
        if (platform != null) ...[
          Flexible(child: _text(platform, mono)),
          if (image != null || avd.abi != null) _Separator(style: text.caption),
        ],
        if (image != null) ...[
          // The raw tag is what sdkmanager package paths use, so it stays one
          // hover away from the label that replaced it.
          Flexible(
            child: Tooltip(
              message: 'System image tag: ${avd.tag}',
              child: _text(image, mono),
            ),
          ),
          if (avd.abi != null) _Separator(style: text.caption),
        ],
        if (avd.abi != null) Flexible(child: _text(avd.abi!, mono)),
      ],
    );
  }

  static Widget _text(String value, TextStyle style) => Text(
    value,
    style: style,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  /// `Android 14 (API 34)`, or whichever half of it the AVD reported.
  static String? _platform(Avd avd) {
    final version = avd.androidVersion;
    final api = avd.apiLevel;
    if (version != null && api != null) return 'Android $version (API $api)';
    if (version != null) return 'Android $version';
    if (api != null) return 'API $api';
    return null;
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('·', style: style),
    );
  }
}
