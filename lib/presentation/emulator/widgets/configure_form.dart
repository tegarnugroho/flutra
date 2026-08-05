import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/emulator/create_emulator_cubit.dart';
import '../../../domain/entities/avd_create_request.dart';
import '../../common/compact_field.dart';
import '../../common/copy_icon_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'device_step.dart' show iconForCategory;
import 'preset_control.dart';
import 'size_dropdown.dart';

/// Step 5: pick a sizing preset, adjust what you care about, see what it costs.
///
/// Everything the average user touches is on the surface; the fields that exist
/// for one project in twenty live under Advanced.
class ConfigureForm extends StatefulWidget {
  const ConfigureForm({super.key, required this.state});

  final CreateEmulatorState state;

  @override
  State<ConfigureForm> createState() => _ConfigureFormState();
}

class _ConfigureFormState extends State<ConfigureForm> {
  late final TextEditingController _nameController;
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.name);
  }

  @override
  void didUpdateWidget(covariant ConfigureForm old) {
    super.didUpdateWidget(old);
    // Sync externally-suggested names in, but don't fight the user mid-typing.
    if (!_nameFocus.hasFocus && widget.state.name != _nameController.text) {
      _nameController.text = widget.state.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    final state = widget.state;
    final config = state.config;
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    void update(EmulatorConfig next) => cubit.updateConfig(next);

    return ListView(
      children: [
        _FieldLabel('Preset'),
        const SizedBox(height: 6),
        PresetControl(
          selected: state.preset,
          onChanged: cubit.selectPreset,
        ),
        const SizedBox(height: 16),

        _FieldLabel('AVD name'),
        const SizedBox(height: 6),
        CompactField(
          controller: _nameController,
          focusNode: _nameFocus,
          icon: null,
          placeholder: 'e.g. Pixel_6_API_34',
          onChanged: cubit.setName,
        ),
        if (state.nameError != null) ...[
          const SizedBox(height: 4),
          Text(
            state.nameError!,
            style: text.caption.copyWith(color: palette.statusError),
          ),
        ],
        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizeDropdown(
                label: 'RAM',
                valueMb: config.ramMb,
                options: _ramOptions(state.hostRamMb),
                unit: SizeUnit.gigabytes,
                minMb: 256,
                maxMb: state.hostRamMb,
                hint: state.hostRamMb == null
                    ? null
                    : 'Host: ${state.hostRamMb! ~/ 1024} GB',
                onChanged: (v) => update(config.copyWith(ramMb: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CoreDropdown(
                cores: config.cpuCores,
                hostCores: state.hostCores,
                onChanged: (v) => update(config.copyWith(cpuCores: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizeDropdown(
                label: 'Internal storage',
                valueMb: config.internalStorageMb,
                options: const [2048, 4096, 6144, 8192, 16384],
                unit: SizeUnit.gigabytes,
                minMb: 1024,
                onChanged: (v) =>
                    update(config.copyWith(internalStorageMb: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _GpuField(config: config, onChanged: update)),
          ],
        ),
        const SizedBox(height: 14),

        _AdvancedSection(
          expanded: state.advancedExpanded,
          onToggle: cubit.toggleAdvanced,
          config: config,
          onChanged: update,
        ),
        const SizedBox(height: 14),

        _SummaryCard(state: state),
      ],
    );
  }

  /// RAM choices, dropping anything past half the host's memory — offering an
  /// emulator bigger than the machine is a trap, not a choice.
  static List<int> _ramOptions(int? hostRamMb) {
    const all = [1024, 2048, 4096, 6144, 8192];
    if (hostRamMb == null) return all;
    final ceiling = hostRamMb ~/ 2;
    final allowed = all.where((mb) => mb <= ceiling).toList();
    return allowed.isEmpty ? [all.first] : allowed;
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(text, style: AppTextStyles.fromPalette(palette).rowLabel);
  }
}

class _GpuField extends StatelessWidget {
  const _GpuField({required this.config, required this.onChanged});

  final EmulatorConfig config;
  final ValueChanged<EmulatorConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('GPU mode'),
        const SizedBox(height: 6),
        CompactCombo<GpuMode>(
          value: config.gpuMode,
          items: [
            for (final mode in GpuMode.values)
              CompactComboItem(value: mode, label: _label(mode)),
          ],
          onChanged: (v) => onChanged(config.copyWith(gpuMode: v)),
        ),
      ],
    );
  }

  static String _label(GpuMode mode) => switch (mode) {
    GpuMode.auto => 'Automatic',
    GpuMode.host => 'Host GPU',
    GpuMode.swiftshaderIndirect => 'Software (SwiftShader)',
    GpuMode.angleIndirect => 'ANGLE',
    GpuMode.guest => 'Guest',
    GpuMode.off => 'Off',
  };
}

/// The fields most people never open: VM heap, SD card, cameras.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.expanded,
    required this.onToggle,
    required this.config,
    required this.onChanged,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final EmulatorConfig config;
  final ValueChanged<EmulatorConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  expanded
                      ? FluentIcons.chevron_down
                      : FluentIcons.chevron_right,
                  size: 10,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 8),
                Text('Advanced', style: text.rowTitle),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'VM heap · SD card · Cameras',
                    style: text.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizeDropdown(
                  label: 'VM heap',
                  valueMb: config.vmHeapMb,
                  options: const [128, 192, 256, 512],
                  unit: SizeUnit.megabytes,
                  minMb: 16,
                  onChanged: (v) => onChanged(config.copyWith(vmHeapMb: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizeDropdown(
                  label: 'SD card',
                  valueMb: config.sdCardMb,
                  options: const [0, 256, 512, 1024],
                  unit: SizeUnit.megabytes,
                  minMb: 0,
                  zeroLabel: 'None',
                  onChanged: (v) => onChanged(config.copyWith(sdCardMb: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AppToggle(
                checked: config.enableCamera,
                onChanged: (v) => onChanged(config.copyWith(enableCamera: v)),
              ),
              const SizedBox(width: 10),
              Text('Front & back cameras', style: text.rowLabel),
            ],
          ),
        ],
      ],
    );
  }
}

/// What the choices add up to, in words rather than package paths.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final option = state.selectedOption;
    final device = state.selectedDevice;
    final config = state.config;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(
            label: 'Device',
            value: _deviceLine(),
            // The raw package path is what you paste into a bug report, so it
            // stays reachable without cluttering the summary.
            trailing: option == null
                ? null
                : CopyIconButton(
                    value: option.packagePath,
                    label: 'Package path',
                  ),
            leading: device == null
                ? null
                : Icon(
                    iconForCategory(device.category),
                    size: 13,
                    color: palette.textSecondary,
                  ),
          ),
          const SizedBox(height: 8),
          _SummaryRow(label: 'Resources', value: _resourceLine(config)),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Disk needed',
            value: _diskLine(),
            valueColor: state.diskTooSmall ? palette.statusError : null,
          ),
          if (state.diskTooSmall) ...[
            const SizedBox(height: 8),
            Text(
              'Only ${_gb(state.freeDiskMb!)} free on the AVD drive',
              style: text.caption.copyWith(color: palette.statusError),
            ),
          ],
        ],
      ),
    );
  }

  String _deviceLine() {
    final device = state.selectedDevice;
    final option = state.selectedOption;
    if (device == null || option == null) return 'Not selected';
    final version = androidVersionOf(option.apiLevel).version;
    final flavour = option.toSystemImage().tagLabel;
    return '${device.name} · $version · $flavour · ${option.abi}';
  }

  static String _resourceLine(EmulatorConfig config) {
    final ram = config.ramMb >= 1024
        ? '${(config.ramMb / 1024).toStringAsFixed(config.ramMb % 1024 == 0 ? 0 : 1)} GB'
        : '${config.ramMb} MB';
    final cores = '${config.cpuCores} core${config.cpuCores == 1 ? '' : 's'}';
    return '$ram RAM · $cores · GPU ${config.gpuMode.iniValue}';
  }

  String _diskLine() {
    final note = state.selectedOption == null
        ? ''
        : state.selectedOption!.installed
        ? ' (image installed)'
        // No number: the catalogue publishes no download size.
        : ' (+ image download)';
    return '~${_gb(state.diskNeededMb)}$note';
  }

  static String _gb(int mb) => mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(1)} GB'
      : '$mb MB';
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.leading,
    this.trailing,
    this.valueColor,
  });

  final String label;
  final String value;
  final Widget? leading;
  final Widget? trailing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: Text(label, style: text.rowLabel)),
        if (leading != null) ...[leading!, const SizedBox(width: 6)],
        Expanded(
          child: Text(
            value,
            style: valueColor == null
                ? text.monoValue
                : text.monoValue.copyWith(color: valueColor),
            textAlign: TextAlign.right,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
  }
}
