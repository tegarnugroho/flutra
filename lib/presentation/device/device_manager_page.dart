import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/device/device_manager_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/device.dart';
import '../common/command_progress_dialog.dart';
import '../common/confirm_dialog.dart';
import '../common/empty_state.dart';
import '../common/grouped_list.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import 'widgets/device_row.dart';

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
    return BlocConsumer<DeviceManagerCubit, DeviceManagerState>(
      listenWhen: (p, c) =>
          c.errorMessage != null && p.errorMessage != c.errorMessage,
      listener: (context, state) {
        displayInfoBar(
          context,
          builder: (context, close) {
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
          },
        );
      },
      builder: (context, state) {
        final cubit = context.read<DeviceManagerCubit>();
        return PageScaffold(
          title: 'Devices',
          actions: [
            OutlinedActionButton(
              icon: FluentIcons.refresh,
              label: 'Refresh',
              busy: state.isLoading,
              onPressed: cubit.load,
            ),
          ],
          child: _body(context, state, cubit),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    DeviceManagerState state,
    DeviceManagerCubit cubit,
  ) {
    return LoadingSwitcher(
      showSkeleton: state.isFirstLoad,
      skeleton: const DeviceListSkeleton(),
      builder: (context) => _loaded(context, state, cubit),
    );
  }

  Widget _loaded(
    BuildContext context,
    DeviceManagerState state,
    DeviceManagerCubit cubit,
  ) {
    if (state.status == DeviceManagerStatus.failure && state.devices.isEmpty) {
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Could not list devices',
        message: state.errorMessage ?? 'Unknown error.',
        actionLabel: 'Retry',
        onAction: cubit.load,
      );
    }
    if (state.devices.isEmpty) {
      return EmptyState(
        icon: FluentIcons.plug_disconnected,
        title: 'No devices connected',
        message:
            'Connect a device over USB (with USB debugging on) or start '
            'an emulator, then refresh.',
        actionLabel: 'Refresh',
        onAction: cubit.load,
      );
    }
    return SingleChildScrollView(
      padding: kPageBodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Connected', meta: '${state.devices.length}'),
          const SizedBox(height: 8),
          GroupedList(
            children: [
              for (final device in state.devices)
                DeviceRow(
                  device: device,
                  busy: state.isBusy(device.serial),
                  actions: DeviceActions(
                    onShell: () => cubit.openShell(device),
                    onLogcat: () => cubit.openLogcat(device),
                    onScreenshot: () => _screenshot(context, cubit, device),
                    onInstallApk: () => _installApk(context, cubit, device),
                    onReboot: (target) =>
                        _reboot(context, cubit, device, target),
                    onDisconnect: () => _disconnect(context, cubit, device),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _screenshot(
    BuildContext context,
    DeviceManagerCubit cubit,
    Device device,
  ) async {
    final path = await cubit.screenshot(device);
    if (path == null || !context.mounted) return;
    await displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('Screenshot saved'),
          content: Text(path),
          severity: InfoBarSeverity.success,
          isLong: true,
          onClose: close,
        );
      },
    );
  }

  Future<void> _installApk(
    BuildContext context,
    DeviceManagerCubit cubit,
    Device device,
  ) async {
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

  Future<void> _reboot(
    BuildContext context,
    DeviceManagerCubit cubit,
    Device device,
    RebootTarget target,
  ) async {
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
    BuildContext context,
    DeviceManagerCubit cubit,
    Device device,
  ) async {
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
