import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/emulator/create_emulator_cubit.dart';
import '../../../domain/entities/device_definition.dart';
import '../../common/compact_field.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Step 1 of the wizard, in two phases: pick a form factor, then a profile
/// inside it.
///
/// Which phase shows is [CreateEmulatorState.devicePhase] — state, not a route,
/// so the stepper and footer stay in charge of the wizard's own navigation.
class DeviceStep extends StatelessWidget {
  const DeviceStep({super.key, required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final categories = state.devicePhase == DeviceStepPhase.categories;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: [...previousChildren, ?currentChild],
      ),
      child: categories
          ? _CategoryPicker(key: const ValueKey('categories'), state: state)
          : _DeviceList(key: const ValueKey('devices'), state: state),
    );
  }
}

/// Icon per form factor. Anything the catalog can't be bucketed into falls
/// back to a generic device glyph.
IconData iconForCategory(DeviceCategory category) => switch (category) {
  DeviceCategory.phone => FluentIcons.cell_phone,
  DeviceCategory.tablet => FluentIcons.tablet,
  DeviceCategory.foldable => FluentIcons.devices3,
  DeviceCategory.wear => FluentIcons.circle_ring,
  DeviceCategory.tv => FluentIcons.t_v_monitor,
  DeviceCategory.automotive => FluentIcons.car,
};

/// Three columns, dropping to two once the content area gets tight.
int _columnsFor(double width) => width < 900 ? 2 : 3;

/// Card heights are fixed rather than derived from an aspect ratio: the grid
/// stretches with the window, and a ratio would grow the cards with it until a
/// two-line device row sat in a 110px box.
/// Horizontal cards at both phases: six categories then fit the default window
/// without scrolling, and the two grids read at the same density.
const _kCategoryCardHeight = 58.0;
const _kDeviceCardHeight = 58.0;

// ---------------------------------------------------------------------------
// Phase 1a — categories
// ---------------------------------------------------------------------------

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({super.key, required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final cubit = context.read<CreateEmulatorCubit>();
    final counts = state.deviceCategoryCounts;
    final categories = state.deviceCategories;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Text('What are you building for?', style: text.rowTitle),
            const SizedBox(height: 3),
            Text(
              'Choose a device category to see available hardware profiles',
              style: text.caption,
            ),
            const SizedBox(height: 14),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: _kCategoryCardHeight,
              ),
              children: [
                for (final category in categories)
                  _CategoryCard(
                    category: category,
                    count: counts[category] ?? 0,
                    onTap: () => cubit.openDeviceCategory(category),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    required this.category,
    required this.count,
    required this.onTap,
  });

  final DeviceCategory category;
  final int count;
  final VoidCallback onTap;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final lifted = _hovered || _focused;

    return _CardShell(
      onTap: widget.onTap,
      onHover: (v) => setState(() => _hovered = v),
      onFocus: (v) => setState(() => _focused = v),
      semanticLabel: '${widget.category.label}, ${widget.count} profiles',
      border: lifted ? palette.borderStrong : palette.border,
      background: lifted ? palette.surfaceRaised : Colors.transparent,
      child: Row(
        children: [
          Icon(
            iconForCategory(widget.category),
            size: 18,
            color: lifted ? palette.textPrimary : palette.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.category.label,
                  style: text.rowTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.count} ${widget.count == 1 ? 'profile' : 'profiles'}',
                  style: text.caption,
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
// Phase 1b — devices in the chosen category
// ---------------------------------------------------------------------------

class _DeviceList extends StatefulWidget {
  const _DeviceList({super.key, required this.state});

  final CreateEmulatorState state;

  @override
  State<_DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<_DeviceList> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Restores the query when the step is re-entered from step 2.
    _search.text = widget.state.deviceQuery;
  }

  @override
  void didUpdateWidget(covariant _DeviceList old) {
    super.didUpdateWidget(old);
    // The cubit clears the query when the category changes; mirror that here
    // without fighting the user mid-typing.
    if (widget.state.deviceQuery.isEmpty && _debounce?.isActive != true) {
      if (_search.text.isNotEmpty) _search.clear();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) context.read<CreateEmulatorCubit>().setDeviceQuery(value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    context.read<CreateEmulatorCubit>().setDeviceQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<CreateEmulatorCubit>();
    final category = state.browsingCategory;
    if (category == null) return const SizedBox.shrink();

    final devices = state.browsedDevices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _Breadcrumb(
                category: category,
                onBack: cubit.showDeviceCategories,
              ),
            ),
            const SizedBox(width: 16),
            CompactField(
              width: 240,
              controller: _search,
              placeholder: 'Search ${category.label}…',
              onChanged: _onQueryChanged,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: devices.isEmpty
              ? _NoMatches(query: state.deviceQuery, onClear: _clearSearch)
              : LayoutBuilder(
                  builder: (context, constraints) => GridView(
                    controller: _scroll,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _columnsFor(constraints.maxWidth),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: _kDeviceCardHeight,
                    ),
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      for (final device in devices)
                        _DeviceCard(
                          device: device,
                          category: category,
                          selected: state.deviceId == device.id,
                          onTap: () => cubit.selectDevice(device.id),
                          onActivate: () {
                            cubit.selectDevice(device.id);
                            cubit.next();
                          },
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.category, required this.onBack});

  final DeviceCategory category;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onBack,
            child: Text(
              'Categories',
              style: text.rowLabel.copyWith(color: palette.accent),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            FluentIcons.chevron_right,
            size: 9,
            color: palette.textMuted,
          ),
        ),
        Flexible(
          child: Text(
            category.label,
            style: text.rowTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No devices match ‘$query’', style: text.statusLine),
          const SizedBox(height: 10),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onClear,
              child: Text(
                'Clear search',
                style: text.rowLabel.copyWith(color: palette.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatefulWidget {
  const _DeviceCard({
    required this.device,
    required this.category,
    required this.selected,
    required this.onTap,
    required this.onActivate,
  });

  final DeviceDefinition device;
  final DeviceCategory category;
  final bool selected;
  final VoidCallback onTap;

  /// Double-click: select and move on.
  final VoidCallback onActivate;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final lifted = _hovered || _focused;
    // TODO(catalog): `avdmanager list device` reports only id, Name and OEM —
    // see `_parseDeviceList`. There is no diagonal, resolution or dpi to build
    // the spec line the design calls for, so the manufacturer stands in. Wire
    // the real specs here once the catalog carries them.
    final spec = widget.device.oem;

    return _CardShell(
      onTap: widget.onTap,
      onDoubleTap: widget.onActivate,
      onHover: (v) => setState(() => _hovered = v),
      onFocus: (v) => setState(() => _focused = v),
      semanticLabel: widget.device.name,
      selected: widget.selected,
      border: widget.selected
          ? palette.accent
          : lifted
          ? palette.borderStrong
          : palette.border,
      borderWidth: widget.selected ? 1.5 : AppShape.hairline,
      background: widget.selected
          ? palette.accentBgTint
          : lifted
          ? palette.surfaceRaised
          : Colors.transparent,
      child: Stack(
        children: [
          Row(
            children: [
              Icon(
                iconForCategory(widget.category),
                size: 18,
                color: widget.selected ? palette.accent : palette.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.device.name,
                      style: text.rowTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (spec != null && spec.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        spec,
                        style: text.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Keeps the label clear of the corner check.
              if (widget.selected) const SizedBox(width: 14),
            ],
          ),
          if (widget.selected)
            Positioned(
              top: 0,
              right: 0,
              child: Icon(
                FluentIcons.check_mark,
                size: 12,
                color: palette.accent,
              ),
            ),
        ],
      ),
    );
  }
}

/// The shared card frame: hairline box, hover/focus lift, and the keyboard
/// wiring that makes arrow keys and Enter work in both grids.
class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.child,
    required this.onTap,
    required this.onHover,
    required this.onFocus,
    required this.semanticLabel,
    required this.border,
    required this.background,
    this.onDoubleTap,
    this.borderWidth = AppShape.hairline,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<bool> onHover;
  final ValueChanged<bool> onFocus;
  final String semanticLabel;
  final Color border;
  final Color background;
  final double borderWidth;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      selected: selected,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: onHover,
        onShowFocusHighlight: onFocus,
        // Enter/Space activate the focused card; the arrow keys are handled by
        // the app's default directional focus traversal.
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: background,
              border: Border.all(color: border, width: borderWidth),
              borderRadius: BorderRadius.circular(AppShape.radiusGroup),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
