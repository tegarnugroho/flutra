import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/device/device_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/device.dart';
import '../common/command_progress_dialog.dart';
import '../emulator/widgets/avd_dialogs.dart';
import 'widgets/device_card.dart';

/// Device Manager: lists connected devices/emulators and their actions.
class DeviceManagerPage extends StatelessWidget {
  const DeviceManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<DeviceManagerCubit>()..load(),
      child: const _DeviceManagerView(),
    );
  }
}

class _DeviceManagerView extends StatelessWidget {
  const _DeviceManagerView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DeviceManagerCubit>();
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Device Manager'),
        commandBar: BlocBuilder<DeviceManagerCubit, DeviceManagerState>(
          builder: (context, state) => CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2))
                    : const Icon(FluentIcons.refresh),
                label: const Text('Refresh'),
                onPressed: state.isLoading ? null : cubit.load,
              ),
            ],
          ),
        ),
      ),
      content: BlocConsumer<DeviceManagerCubit, DeviceManagerState>(
        listenWhen: (p, c) =>
            c.errorMessage != null && p.errorMessage != c.errorMessage,
        listener: (context, state) {
          displayInfoBar(context, builder: (context, close) {
            return InfoBar(
              title: const Text('Error'),
              content: Text(state.errorMessage!),
              severity: InfoBarSeverity.error,
              isLong: true,
              onClose: () {
                close();
                context.read<DeviceManagerCubit>().clearError();
              },
            );
          });
        },
        builder: (context, state) {
          if (state.isLoading && state.devices.isEmpty) {
            return const Center(child: ProgressRing());
          }
          if (state.status == DeviceManagerStatus.failure &&
              state.devices.isEmpty) {
            return _CenteredMessage(
              icon: FluentIcons.error_badge,
              title: 'Could not list devices',
              message: state.errorMessage ?? 'Unknown error.',
              actionLabel: 'Retry',
              onAction: cubit.load,
            );
          }
          if (state.devices.isEmpty) {
            return _CenteredMessage(
              icon: FluentIcons.plug_disconnected,
              title: 'No devices connected',
              message: 'Connect a device over USB (with USB debugging on) or '
                  'start an emulator, then refresh.',
              actionLabel: 'Refresh',
              onAction: cubit.load,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: state.devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final device = state.devices[i];
              return DeviceCard(
                device: device,
                busy: state.isBusy(device.serial),
                actions: DeviceActions(
                  onShell: () => cubit.openShell(device),
                  onLogcat: () => cubit.openLogcat(device),
                  onScreenshot: () => _screenshot(context, cubit, device),
                  onInstallApk: () => _installApk(context, cubit, device),
                  onReboot: (target) => _reboot(context, cubit, device, target),
                  onDisconnect: () => _disconnect(context, cubit, device),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _screenshot(
      BuildContext context, DeviceManagerCubit cubit, Device device) async {
    final path = await cubit.screenshot(device);
    if (path == null || !context.mounted) return;
    await displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('Screenshot saved'),
        content: Text(path),
        severity: InfoBarSeverity.success,
        isLong: true,
        onClose: close,
      );
    });
  }

  Future<void> _installApk(
      BuildContext context, DeviceManagerCubit cubit, Device device) async {
    final path = await showTextPromptDialog(
      context,
      title: 'Install APK on ${device.displayName}',
      label: 'Full path to the .apk file',
      confirmLabel: 'Install',
    );
    if (path == null || !context.mounted) return;
    await showCommandProgressDialog(
      context,
      title: 'Installing APK',
      start: () => cubit.installApk(device, path),
    );
  }

  Future<void> _reboot(BuildContext context, DeviceManagerCubit cubit,
      Device device, RebootTarget target) async {
    final label = switch (target) {
      RebootTarget.system => 'reboot',
      RebootTarget.bootloader => 'reboot to bootloader',
      RebootTarget.recovery => 'reboot to recovery',
    };
    final ok = await showConfirmDialog(
      context,
      title: 'Reboot ${device.displayName}?',
      message: 'This will $label the device now.',
      confirmLabel: 'Reboot',
      destructive: false,
    );
    if (ok) cubit.reboot(device, target);
  }

  Future<void> _disconnect(
      BuildContext context, DeviceManagerCubit cubit, Device device) async {
    final emulator = device.isEmulator;
    final ok = await showConfirmDialog(
      context,
      title: emulator
          ? 'Stop ${device.displayName}?'
          : 'Disconnect ${device.displayName}?',
      message: emulator
          ? 'The running emulator will be shut down.'
          : 'The device will be disconnected from adb.',
      confirmLabel: emulator ? 'Stop' : 'Disconnect',
    );
    if (ok) cubit.disconnect(device);
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
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
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
