import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/emulator/create_emulator_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/system_image.dart';
import '../common/app_loader.dart';
import '../common/confirm_dialog.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'widgets/configure_form.dart';
import 'widgets/device_step.dart';
import 'widgets/install_badge.dart';
import 'widgets/wizard_option_row.dart';
import 'widgets/wizard_footer.dart';
import 'widgets/wizard_stepper.dart';
import '../common/task_window_title_bar.dart';

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
    final cubit = context.read<CreateEmulatorCubit>();
    final state = cubit.state;
    if (state.deviceId == null && !state.isWorking) {
      _close(context, false);
      return;
    }
    _leaving = true;
    // A running download is worth naming: leaving throws away a partial
    // multi-hundred-megabyte fetch, not just a few clicks.
    final discard = await showConfirmDialog(
      context,
      title: state.isWorking
          ? 'A download is in progress'
          : 'Discard this emulator?',
      message: state.isWorking
          ? 'Cancel it and close the wizard?'
          : 'The device you picked and any other choices will be lost.',
      confirmLabel: state.isWorking ? 'Cancel & close' : 'Discard',
    );
    _leaving = false;
    if (!discard) return;
    if (state.isWorking) cubit.cancelInstall();
    if (context.mounted) _close(context, false);
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
            TaskWindowTitleBar(
              title: 'Create emulator',
              leading: TitleBarIconButton(
                icon: FluentIcons.back,
                tooltip: atStart ? 'Close' : 'Back to categories',
                onPressed: () {
                  if (!context.read<CreateEmulatorCubit>().back()) {
                    _exit(context);
                  }
                },
              ),
              trailing: state.selectedDevice == null
                  ? null
                  : TitleBarChip(label: state.selectedDevice!.name),
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
          if (state.options.isEmpty) {
            return const _CenteredMessage(
              icon: FluentIcons.download,
              title: 'No system images available',
              message:
                  'sdkmanager reported no system-image packages. Check the '
                  'SDK path in Settings, then try again.',
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
                  kTaskWindowInset,
                  2,
                  kTaskWindowInset,
                  10,
                ),
                child: _StepContent(state: state),
              ),
            ),
            WizardFooter(
              summary: state.isWorking
                  ? _InstallProgress(state: state)
                  : _FooterSummary(state: state),
              // A running install owns the left button: it aborts the
              // download instead of stepping the wizard back under it.
              backLabel: state.isWorking
                  ? 'Cancel'
                  : (state.step == WizardStep.device &&
                        state.devicePhase == DeviceStepPhase.categories)
                  ? 'Cancel'
                  : 'Back',
              onBack: state.isWorking ? cubit.cancelInstall : goBack,
              onNext: isLast
                  ? (state.canAdvance && !state.submitting
                        ? cubit.submit
                        : null)
                  : (state.canAdvance ? cubit.next : null),
              nextLabel: isLast
                  ? (state.errorMessage != null
                        ? 'Retry'
                        : state.needsDownload
                        ? 'Download & create'
                        : 'Create emulator')
                  : 'Next',
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

/// The footer while the deferred download and AVD creation run.
///
/// Determinate whenever sdkmanager prints a percentage; otherwise the phase
/// label alone carries the state, which is honest about what is knowable.
class _InstallProgress extends StatelessWidget {
  const _InstallProgress({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final progress = state.installProgress;
    return Row(
      children: [
        const AppLoader(size: AppLoaderSize.small),
        const SizedBox(width: 10),
        Text(state.installPhase.label, style: text.statusLine),
        if (progress != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: ProgressBar(
              value: progress * 100,
              activeColor: palette.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text('${(progress * 100).round()}%', style: text.caption),
        ],
      ],
    );
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
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    return ListView(
      children: [
        Text('Android version', style: text.rowTitle),
        const SizedBox(height: 3),
        Text(
          'Versions without an image will be downloaded when the emulator is '
          'created',
          style: text.caption,
        ),
        const SizedBox(height: 12),
        for (final api in state.visibleApiLevels)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ApiRow(
              api: api,
              installed: state.isApiInstalled(api),
              selected: state.apiLevel == api,
              onTap: () => cubit.selectApiLevel(api),
            ),
          ),
        if (state.olderApiLevels.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: _LinkButton(
              label: state.showOlderApis
                  ? 'Hide older versions'
                  : 'Show older versions (${state.olderApiLevels.length})',
              onTap: cubit.toggleOlderApis,
            ),
          ),
        if (state.apiLevel != null && !state.isApiInstalled(state.apiLevel!))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DeferredDownloadBanner(
              message:
                  '${androidVersionOf(state.apiLevel!).version} is not '
                  'installed yet — the system image will download during '
                  'creation',
            ),
          ),
      ],
    );
  }
}

/// One Android version: name + API on the left, install state on the right.
class _ApiRow extends StatelessWidget {
  const _ApiRow({
    required this.api,
    required this.installed,
    required this.selected,
    required this.onTap,
  });

  final int api;
  final bool installed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final version = androidVersionOf(api);
    return WizardOptionRow(
      selected: selected,
      onTap: onTap,
      title: '${version.version} · API $api',
      subtitle: version.codename,
      trailing: InstallBadge(installed: installed),
    );
  }
}

/// A quiet text button for in-list affordances (expanders, clear actions).
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: text.rowLabel.copyWith(color: palette.accent),
          ),
        ),
      ),
    );
  }
}

// ---- Step 3: image tag ------------------------------------------------------

class _ImageStep extends StatelessWidget {
  const _ImageStep({required this.state});

  final CreateEmulatorState state;

  /// The flavour most projects want: Google APIs without the Play Store.
  static const _recommendedTag = 'google_apis';

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final selectedMissing =
        state.tag != null && !state.isTagInstalled(state.tag!);

    return ListView(
      children: [
        Text('System image', style: text.rowTitle),
        const SizedBox(height: 3),
        Text(
          'Flavours available for API ${state.apiLevel}',
          style: text.caption,
        ),
        const SizedBox(height: 12),
        for (final tag in state.tagsForApi)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: WizardOptionRow(
              selected: state.tag == tag,
              onTap: () => cubit.selectTag(tag),
              title: _tagLabel(tag),
              subtitle: tag,
              leading: tag == _recommendedTag ? const RecommendedTag() : null,
              trailing: InstallBadge(installed: state.isTagInstalled(tag)),
            ),
          ),
        if (selectedMissing)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DeferredDownloadBanner(
              message:
                  '${_tagLabel(state.tag!)} is not installed yet — it will '
                  'download during creation',
            ),
          ),
      ],
    );
  }

  /// Friendly name for a tag, without needing an installed image to ask.
  static String _tagLabel(String tag) => SystemImage(
    packagePath: '',
    platform: '',
    apiLevel: 0,
    tag: tag,
    abi: '',
  ).tagLabel;
}

// ---- Step 4: ABI ------------------------------------------------------------

class _AbiStep extends StatelessWidget {
  const _AbiStep({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateEmulatorCubit>();
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final option = state.selectedOption;

    return ListView(
      children: [
        Text('ABI', style: text.rowTitle),
        const SizedBox(height: 3),
        Text(
          'Only ABIs published for this image are listed',
          style: text.caption,
        ),
        const SizedBox(height: 12),
        for (final abi in state.abisForSelection)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: WizardOptionRow(
              selected: state.abi == abi,
              onTap: () => cubit.selectAbi(abi),
              title: abi,
              subtitle: abi.startsWith('x86')
                  ? 'Intel/AMD — fastest on this PC'
                  : 'ARM — slower via translation',
              trailing: InstallBadge(
                // Per exact package now, not per flavour.
                installed: state.optionForAbi(abi)?.installed ?? false,
              ),
            ),
          ),
        if (option != null && !option.installed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DeferredDownloadBanner(
              message:
                  '${option.packagePath} will download when the emulator is '
                  'created',
            ),
          ),
      ],
    );
  }
}

// ---- Step 5: configuration --------------------------------------------------

class _ConfigureStep extends StatelessWidget {
  const _ConfigureStep({required this.state});

  final CreateEmulatorState state;

  @override
  Widget build(BuildContext context) => ConfigureForm(state: state);
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
