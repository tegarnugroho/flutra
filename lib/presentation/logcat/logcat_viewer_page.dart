import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/log/live_log_cubit.dart';
import '../../application/log/logcat_devices_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/repositories/device_repository.dart';
import '../common/compact_field.dart';
import '../common/empty_state.dart';
import '../common/live_log_view.dart';
import '../common/log_toolbar.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/status_dot.dart';
import '../theme/app_colors.dart';

/// Logcat Viewer: streams `adb logcat` from a selected device with live
/// priority/tag/text filtering.
class LogcatViewerPage extends StatefulWidget {
  const LogcatViewerPage({super.key});

  @override
  State<LogcatViewerPage> createState() => _LogcatViewerPageState();
}

class _LogcatViewerPageState extends State<LogcatViewerPage> {
  final DeviceRepository _devices = getIt<DeviceRepository>();
  final LiveLogCubit _log = LiveLogCubit(parseLogcat: true);
  final LogcatDevicesCubit _deviceList = getIt<LogcatDevicesCubit>();

  @override
  void initState() {
    super.initState();
    _deviceList.load();
  }

  @override
  void dispose() {
    _log.close();
    _deviceList.close();
    super.dispose();
  }

  void _start(String? serial) {
    if (serial == null) return;
    _log.start(() => _devices.streamLogcat(serial));
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _log),
        BlocProvider.value(value: _deviceList),
      ],
      // Restart the stream whenever the selected device changes — including
      // the first selection made by the initial load.
      child: BlocConsumer<LogcatDevicesCubit, LogcatDevicesState>(
        listenWhen: (prev, curr) => prev.serial != curr.serial,
        listener: (context, devices) => _start(devices.serial),
        builder: (context, devices) {
          return PageScaffold(
            title: 'Logcat',
            actions: [
              OutlinedActionButton(
                icon: FluentIcons.refresh,
                label: 'Devices',
                busy: devices.isLoading,
                onPressed: _deviceList.load,
              ),
            ],
            child: devices.isEmpty
                ? EmptyState(
                    icon: FluentIcons.plug_disconnected,
                    title: 'No online devices',
                    message:
                        'Connect a device or start an emulator, then refresh.',
                    actionLabel: 'Refresh',
                    onAction: _deviceList.load,
                  )
                : BlocBuilder<LiveLogCubit, LiveLogState>(
                    builder: (context, state) {
                      final filtered = state.filtered;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                CompactCombo<String>(
                                  width: 240,
                                  value: devices.serial,
                                  placeholder: 'Select device',
                                  items: [
                                    for (final d in devices.online)
                                      CompactComboItem(
                                        value: d.serial,
                                        label: '${d.displayName} (${d.serial})',
                                      ),
                                  ],
                                  onChanged: _deviceList.select,
                                ),
                                LogToolbar(
                                  cubit: _log,
                                  state: state,
                                  showPriority: true,
                                  showTag: true,
                                  savePrefix: 'logcat',
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            child: _StatusLine(
                                state: state, count: filtered.length),
                          ),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: LiveLogView(
                                lines: filtered,
                                emptyHint: state.isStarting
                                    ? 'Starting logcat…'
                                    : 'No matching log lines.',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

/// Stream state as the app's standard dot + one-line summary.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state, required this.count});

  final LiveLogState state;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (color, label) = switch (state.status) {
      LiveLogStatus.running => (
          palette.statusOk,
          state.paused ? 'Paused' : 'Streaming'
        ),
      LiveLogStatus.starting => (palette.statusWarn, 'Starting'),
      LiveLogStatus.stopped => (palette.textMuted, 'Stopped'),
      LiveLogStatus.failure => (palette.statusError, 'Error'),
      LiveLogStatus.idle => (palette.textMuted, 'Idle'),
    };
    final message = state.errorMessage != null
        ? '$label — ${state.errorMessage}'
        : '$label · $count lines';
    return StatusLine(
      color: state.paused ? palette.textMuted : color,
      message: state.paused ? 'Paused · $count lines' : message,
    );
  }
}
