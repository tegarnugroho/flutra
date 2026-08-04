import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/emulator/create_emulator_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/avd_create_request.dart';
import '../../domain/entities/device_definition.dart';
import '../../domain/entities/system_image.dart';
import 'widgets/select_tile.dart';
import '../theme/app_colors.dart';

/// Multi-step wizard for creating a new AVD.
///
/// When [onClose] is provided the wizard is embedded inside another screen and
/// reports completion (`true` = created) via the callback; otherwise it assumes
/// it was pushed as a route and pops the navigator.
class CreateEmulatorPage extends StatelessWidget {
  const CreateEmulatorPage({super.key, this.onClose});

  final void Function(bool created)? onClose;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CreateEmulatorCubit>()..load(),
      child: _CreateEmulatorView(onClose: onClose),
    );
  }
}

class _CreateEmulatorView extends StatelessWidget {
  const _CreateEmulatorView({this.onClose});

  final void Function(bool created)? onClose;

  void _close(BuildContext context, bool created) {
    if (onClose != null) {
      onClose!(created);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Create Emulator'),
        leading: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            icon: const Icon(FluentIcons.back, size: 16),
            onPressed: () => _close(context, false),
          ),
        ),
      ),
      content: BlocConsumer<CreateEmulatorCubit, CreateEmulatorState>(
        listenWhen: (p, c) => p.createdName != c.createdName,
        listener: (context, state) {
          if (state.isSuccess) _showSuccess(context, state.createdName!);
        },
        builder: (context, state) {
          if (state.loadStatus == LoadStatus.loading) {
            return const Center(child: ProgressRing());
          }
          if (state.loadStatus == LoadStatus.failure) {
            return _CenteredMessage(
              icon: FluentIcons.error_badge,
              title: 'Could not load options',
              message: state.errorMessage ?? 'Unknown error.',
            );
          }
          if (state.images.isEmpty) {
            return const _CenteredMessage(
              icon: FluentIcons.download,
              title: 'No system images installed',
              message: 'Install at least one system image from the SDK Manager '
                  '(e.g. "system-images;android-34;google_apis;x86_64") before '
                  'creating an emulator.',
            );
          }
          return _WizardBody(state: state);
        },
      ),
    );
  }

  void _showSuccess(BuildContext context, String name) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: const Text('Emulator created'),
        content: Text('"$name" was created successfully.'),
        actions: [
          Button(
            child: const Text('Create another'),
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<CreateEmulatorCubit>().createAnother();
            },
          ),
          FilledButton(
            child: const Text('Back to list'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _close(context, true);
            },
          ),
        ],
      ),
    );
  }
}

class _WizardBody extends StatelessWidget {
  const _WizardBody({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    return Column(
      children: [
        _StepIndicator(current: state.step, onTap: cubit.goTo),
        const Divider(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: _StepContent(state: state),
          ),
        ),
        _WizardFooter(state: state),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.onTap});

  final WizardStep current;
  final ValueChanged<WizardStep> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Row(
        children: [
          for (final step in WizardStep.values) ...[
            _dot(theme, step),
            if (step != WizardStep.values.last)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: step.index < current.index
                      ? theme.accentColor
                      : theme.resources.controlStrokeColorDefault,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _dot(FluentThemeData theme, WizardStep step) {
    final done = step.index < current.index;
    final active = step == current;
    final color =
        active || done ? theme.accentColor : theme.resources.controlStrokeColorDefault;
    return GestureDetector(
      onTap: step.index <= current.index ? () => onTap(step) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? theme.accentColor
                  : done
                      ? theme.accentColor.withValues(alpha: 0.2)
                      : Colors.transparent,
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(
              child: done
                  ? Icon(FluentIcons.check_mark,
                      size: 12, color: active ? Colors.white : theme.accentColor)
                  : Text('${step.index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: active
                            ? Colors.white
                            : theme.resources.textFillColorSecondary,
                      )),
            ),
          ),
          const SizedBox(height: 4),
          Text(step.title,
              style: theme.typography.caption?.copyWith(
                color: active
                    ? theme.accentColor
                    : theme.resources.textFillColorTertiary,
              )),
        ],
      ),
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.step) {
      WizardStep.device => _DeviceStep(state: state),
      WizardStep.apiLevel => _ApiStep(state: state),
      WizardStep.image => _ImageStep(state: state),
      WizardStep.abi => _AbiStep(state: state),
      WizardStep.configure => _ConfigureStep(state: state),
    };
  }
}

// ---- Step 1: device ---------------------------------------------------------

class _DeviceStep extends StatelessWidget {
  const _DeviceStep({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    final byCategory = <DeviceCategory, List<DeviceDefinition>>{};
    for (final d in state.devices) {
      byCategory.putIfAbsent(d.category, () => []).add(d);
    }
    final categories = DeviceCategory.values
        .where((c) => byCategory.containsKey(c))
        .toList();

    return ListView(
      children: [
        for (final category in categories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(category.label,
                style: FluentTheme.of(context).typography.bodyStrong),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final device in byCategory[category]!)
                SizedBox(
                  width: 240,
                  child: SelectTile(
                    icon: _iconFor(category),
                    title: device.name,
                    subtitle: device.oem,
                    selected: state.deviceId == device.id,
                    onTap: () => cubit.selectDevice(device.id),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  IconData _iconFor(DeviceCategory c) => switch (c) {
        DeviceCategory.phone => FluentIcons.cell_phone,
        DeviceCategory.tablet => FluentIcons.tablet,
        DeviceCategory.foldable => FluentIcons.devices3,
        DeviceCategory.wear => FluentIcons.circle_ring,
        DeviceCategory.tv => FluentIcons.t_v_monitor,
        DeviceCategory.automotive => FluentIcons.car,
      };
}

// ---- Step 2: API level ------------------------------------------------------

class _ApiStep extends StatelessWidget {
  const _ApiStep({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    return ListView(
      children: [
        for (final api in state.availableApiLevels)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SelectTile(
              icon: FluentIcons.build_queue,
              title: 'Android API $api',
              subtitle: _codeName(api),
              selected: state.apiLevel == api,
              onTap: () => cubit.selectApiLevel(api),
            ),
          ),
      ],
    );
  }

  String _codeName(int api) => switch (api) {
        36 => 'Android 16',
        35 => 'Android 15 (VanillaIceCream)',
        34 => 'Android 14 (UpsideDownCake)',
        33 => 'Android 13 (Tiramisu)',
        32 || 31 => 'Android 12 (S)',
        30 => 'Android 11 (R)',
        29 => 'Android 10 (Q)',
        _ => 'API level $api',
      };
}

// ---- Step 3: image tag ------------------------------------------------------

class _ImageStep extends StatelessWidget {
  const _ImageStep({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    return ListView(
      children: [
        for (final tag in state.tagsForApi)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SelectTile(
              icon: tag.contains('playstore')
                  ? FluentIcons.shop
                  : tag.contains('google')
                      ? FluentIcons.cloud
                      : FluentIcons.app_icon_default,
              title: _label(state, tag),
              subtitle: tag,
              selected: state.tag == tag,
              onTap: () => cubit.selectTag(tag),
            ),
          ),
      ],
    );
  }

  String _label(CreateEmulatorState state, String tag) {
    final match = state.images.firstWhere(
      (i) => i.apiLevel == state.apiLevel && i.tag == tag,
      orElse: () => SystemImage(
          packagePath: '', platform: '', apiLevel: 0, tag: tag, abi: ''),
    );
    return match.tagLabel;
  }
}

// ---- Step 4: ABI ------------------------------------------------------------

class _AbiStep extends StatelessWidget {
  const _AbiStep({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    return ListView(
      children: [
        for (final abi in state.abisForSelection)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SelectTile(
              icon: FluentIcons.processing,
              title: abi,
              subtitle: abi.startsWith('x86')
                  ? 'Intel/AMD — fastest on this PC'
                  : 'ARM — slower via translation',
              selected: state.abi == abi,
              onTap: () => cubit.selectAbi(abi),
            ),
          ),
      ],
    );
  }
}

// ---- Step 5: configuration --------------------------------------------------

class _ConfigureStep extends StatefulWidget {
  const _ConfigureStep({required this.state});

  final CreateEmulatorState state;

  @override
  State<_ConfigureStep> createState() => _ConfigureStepState();
}

class _ConfigureStepState extends State<_ConfigureStep> {
  late final TextEditingController _nameController;
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.name);
  }

  @override
  void didUpdateWidget(covariant _ConfigureStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync externally-suggested names in, but don't fight the user while typing.
    if (!_nameFocus.hasFocus &&
        widget.state.name != _nameController.text) {
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

    return ListView(
      children: [
        InfoLabel(
          label: 'AVD name',
          child: TextBox(
            controller: _nameController,
            focusNode: _nameFocus,
            placeholder: 'e.g. Pixel_6_API_34',
            onChanged: cubit.setName,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _numberField(
                'RAM (MB)',
                config.ramMb,
                (v) => cubit.updateConfig(config.copyWith(ramMb: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                'VM heap (MB)',
                config.vmHeapMb,
                (v) => cubit.updateConfig(config.copyWith(vmHeapMb: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _numberField(
                'Internal storage (MB)',
                config.internalStorageMb,
                (v) =>
                    cubit.updateConfig(config.copyWith(internalStorageMb: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                'SD card (MB, 0 = none)',
                config.sdCardMb,
                (v) => cubit.updateConfig(config.copyWith(sdCardMb: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _numberField(
                'CPU cores',
                config.cpuCores,
                (v) => cubit.updateConfig(config.copyWith(cpuCores: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InfoLabel(
                label: 'GPU mode',
                child: ComboBox<GpuMode>(
                  isExpanded: true,
                  value: config.gpuMode,
                  items: [
                    for (final mode in GpuMode.values)
                      ComboBoxItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (v) => v == null
                      ? null
                      : cubit.updateConfig(config.copyWith(gpuMode: v)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ToggleSwitch(
          checked: config.enableCamera,
          onChanged: (v) =>
              cubit.updateConfig(config.copyWith(enableCamera: v)),
          content: const Text('Enable cameras (front & back)'),
        ),
        const SizedBox(height: 20),
        _summary(context, state),
      ],
    );
  }

  Widget _numberField(String label, int value, ValueChanged<int> onChanged) {
    return InfoLabel(
      label: label,
      child: NumberBox<int>(
        value: value,
        mode: SpinButtonPlacementMode.inline,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _summary(BuildContext context, CreateEmulatorState state) {
    final theme = FluentTheme.of(context);
    final image = state.selectedImage;
    final rows = <(String, String)>[
      ('Device', state.selectedDevice?.name ?? state.deviceId ?? '—'),
      ('System image', image?.packagePath ?? '—'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Summary', style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 110,
                      child: Text(row.$1,
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ))),
                  Expanded(
                      child: Text(row.$2, style: theme.typography.caption)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---- Footer -----------------------------------------------------------------

class _WizardFooter extends StatelessWidget {
  const _WizardFooter({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    final isLast = state.step == WizardStep.values.last;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: FluentTheme.of(context).resources.controlStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          if (state.errorMessage != null)
            Expanded(
              child: Text(
                state.errorMessage!,
                style: const TextStyle(color: AppColors.statusError),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          Button(
            onPressed: state.step.index == 0 ? null : cubit.back,
            child: const Text('Back'),
          ),
          const SizedBox(width: 10),
          if (isLast)
            FilledButton(
              onPressed:
                  state.canAdvance && !state.submitting ? cubit.submit : null,
              child: state.submitting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            width: 14,
                            height: 14,
                            child: ProgressRing(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Creating…'),
                      ],
                    )
                  : const Text('Create emulator'),
            )
          else
            FilledButton(
              onPressed: state.canAdvance ? cubit.next : null,
              child: const Text('Next'),
            ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.resources.textFillColorTertiary),
            const SizedBox(height: 14),
            Text(title, style: theme.typography.subtitle),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.typography.body?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                )),
          ],
        ),
      ),
    );
  }
}
