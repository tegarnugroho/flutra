import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/emulator/create_emulator_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/avd_create_request.dart';
import '../../domain/entities/system_image.dart';
import '../common/app_loader.dart';
import '../common/confirm_dialog.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'widgets/device_step.dart';
import 'widgets/select_tile.dart';
import 'widgets/wizard_footer.dart';
import 'widgets/wizard_stepper.dart';
import 'widgets/wizard_title_bar.dart';

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

class _CreateEmulatorView extends StatefulWidget {
  const _CreateEmulatorView({this.onClose});

  final void Function(bool created)? onClose;

  @override
  State<_CreateEmulatorView> createState() => _CreateEmulatorViewState();
}

/// Owns the window-close hook: the caption X and the footer's Cancel must run
/// the same discard check, so the listener lives where the cubit is readable.
class _CreateEmulatorViewState extends State<_CreateEmulatorView>
    with WindowListener {
  /// Set while the discard prompt is up, so hammering the X or Cancel can't
  /// stack a second dialog on top of the first.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows) return;
    windowManager.addListener(this);
    // Intercept the native close so an accidental X can still be taken back.
    windowManager.setPreventClose(true).catchError((_) {});
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    _exit(context);
  }

  void _close(BuildContext context, bool created) {
    if (widget.onClose != null) {
      widget.onClose!(created);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(created);
    }
  }

  /// Leaving the wizard from its first screen. Only asks when there is
  /// something to lose — a device the user already picked.
  Future<void> _exit(BuildContext context) async {
    if (_leaving) return;
    final state = context.read<CreateEmulatorCubit>().state;
    if (state.deviceId == null) {
      _close(context, false);
      return;
    }
    _leaving = true;
    final discard = await showConfirmDialog(
      context,
      title: 'Discard this emulator?',
      message: 'The device you picked and any other choices will be lost.',
      confirmLabel: 'Discard',
    );
    _leaving = false;
    if (discard && context.mounted) _close(context, false);
  }

  @override
  Widget build(BuildContext context) {
    // The window's caption *is* the header — no second heading below it.
    return BlocBuilder<CreateEmulatorCubit, CreateEmulatorState>(
      buildWhen: (p, c) =>
          p.devicePhase != c.devicePhase ||
          p.step != c.step ||
          p.deviceId != c.deviceId,
      builder: (context, state) {
        final atStart =
            state.step == WizardStep.device &&
            state.devicePhase == DeviceStepPhase.categories;
        return Column(
          children: [
            WizardTitleBar(
              backTooltip: atStart ? 'Close' : 'Back to categories',
              contextLabel: state.selectedDevice?.name,
              onBack: () {
                if (!context.read<CreateEmulatorCubit>().back()) _exit(context);
              },
              onClose: () => _exit(context),
            ),
            Expanded(child: _content()),
          ],
        );
      },
    );
  }

  Widget _content() {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: BlocConsumer<CreateEmulatorCubit, CreateEmulatorState>(
        listenWhen: (p, c) => p.createdName != c.createdName,
        listener: (context, state) {
          if (state.isSuccess) _showSuccess(context, state.createdName!);
        },
        builder: (context, state) {
          if (state.loadStatus == LoadStatus.loading) {
            return const Center(child: AppLoader(size: AppLoaderSize.large));
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
              message:
                  'Install at least one system image from the SDK Manager '
                  '(e.g. "system-images;android-34;google_apis;x86_64") before '
                  'creating an emulator.',
            );
          }
          return _WizardBody(state: state, onExit: () => _exit(context));
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
  const _WizardBody({required this.state, required this.onExit});

  final CreateEmulatorState state;

  /// Called when Back (or Esc) runs out of wizard to go back through.
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    final isLast = state.step == WizardStep.values.last;

    void goBack() {
      if (!cubit.back()) onExit();
    }

    return CallbackShortcuts(
      // Esc mirrors Back at every level: device list → categories → out.
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): goBack},
      child: FocusScope(
        autofocus: true,
        child: Column(
          children: [
            WizardStepper(current: state.step, onTap: cubit.goTo),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  kWizardInset,
                  2,
                  kWizardInset,
                  10,
                ),
                child: _StepContent(state: state),
              ),
            ),
            WizardFooter(
              summary: _FooterSummary(state: state),
              backLabel:
                  state.step == WizardStep.device &&
                      state.devicePhase == DeviceStepPhase.categories
                  ? 'Cancel'
                  : 'Back',
              onBack: goBack,
              onNext: isLast
                  ? (state.canAdvance && !state.submitting
                        ? cubit.submit
                        : null)
                  : (state.canAdvance ? cubit.next : null),
              nextLabel: isLast ? 'Create emulator' : 'Next',
              nextDisabledTooltip: _nextBlockedReason(state),
              busy: state.submitting,
            ),
          ],
        ),
      ),
    );
  }

  /// Why the primary action is unavailable, or null when it is available.
  static String? _nextBlockedReason(CreateEmulatorState state) {
    if (state.canAdvance) return null;
    return switch (state.step) {
      WizardStep.device => 'Choose a device first',
      WizardStep.apiLevel => 'Choose an Android version first',
      WizardStep.image => 'Choose a system image first',
      WizardStep.abi => 'Choose an ABI first',
      WizardStep.configure => 'Name the emulator first',
    };
  }
}

/// The footer's left slot: the error if there is one, otherwise what the user
/// has picked so far.
class _FooterSummary extends StatelessWidget {
  const _FooterSummary({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    if (state.errorMessage != null) {
      return Text(
        state.errorMessage!,
        style: text.statusLine.copyWith(color: palette.statusError),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final device = state.selectedDevice;
    // Picking a category is not picking a device, so the category phase always
    // asks for one — even when a device is already selected underneath.
    if (device == null || state.devicePhase == DeviceStepPhase.categories) {
      return Text(
        'Select a device to continue',
        style: text.statusLine.copyWith(color: palette.textMuted),
      );
    }
    return Row(
      children: [
        Icon(
          iconForCategory(device.category),
          size: 16,
          color: palette.textSecondary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            device.name,
            style: text.rowTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (device.oem != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              device.oem!,
              style: text.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.step) {
      WizardStep.device => DeviceStep(state: state),
      WizardStep.apiLevel => _ApiStep(state: state),
      WizardStep.image => _ImageStep(state: state),
      WizardStep.abi => _AbiStep(state: state),
      WizardStep.configure => _ConfigureStep(state: state),
    };
  }
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
        packagePath: '',
        platform: '',
        apiLevel: 0,
        tag: tag,
        abi: '',
      ),
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
                    child: Text(
                      row.$1,
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(row.$2, style: theme.typography.caption),
                  ),
                ],
              ),
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
