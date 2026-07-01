import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/log/live_log_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/device.dart';
import '../../domain/repositories/device_repository.dart';
import '../common/live_log_view.dart';
import '../common/log_toolbar.dart';

/// Logcat Viewer: streams `adb logcat` from a selected device with live
/// priority/tag/text filtering.
class LogcatViewerPage extends StatefulWidget {
  const LogcatViewerPage({super.key});

  @override
  State<LogcatViewerPage> createState() => _LogcatViewerPageState();
}

class _LogcatViewerPageState extends State<LogcatViewerPage> {
  final DeviceRepository _devices = getIt<DeviceRepository>();
  final LiveLogCubit _cubit = LiveLogCubit(parseLogcat: true);

  List<Device> _online = const [];
  String? _serial;
  bool _loadingDevices = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final all = await _devices.listDevices();
      final online = all.where((d) => d.state.isOnline).toList();
      if (!mounted) return;
      setState(() {
        _online = online;
        _serial ??= online.isNotEmpty ? online.first.serial : null;
      });
      if (_serial != null) _start();
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  void _start() {
    final serial = _serial;
    if (serial == null) return;
    _cubit.start(() => _devices.streamLogcat(serial));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: ScaffoldPage(
        header: PageHeader(
          title: const Text('Logcat Viewer'),
          commandBar: CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: _loadingDevices
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2))
                    : const Icon(FluentIcons.refresh),
                label: const Text('Devices'),
                onPressed: _loadingDevices ? null : _loadDevices,
              ),
            ],
          ),
        ),
        content: _online.isEmpty && !_loadingDevices
            ? _NoDevices(onRefresh: _loadDevices)
            : BlocBuilder<LiveLogCubit, LiveLogState>(
                builder: (context, state) {
                  final filtered = state.filtered;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 260,
                              child: ComboBox<String>(
                                isExpanded: true,
                                placeholder: const Text('Select device'),
                                value: _serial,
                                items: [
                                  for (final d in _online)
                                    ComboBoxItem(
                                      value: d.serial,
                                      child: Text(
                                        '${d.displayName} (${d.serial})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) {
                                  setState(() => _serial = v);
                                  _start();
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: LogToolbar(
                                cubit: _cubit,
                                state: state,
                                showPriority: true,
                                showTag: true,
                                savePrefix: 'logcat',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _StatusLine(state: state, count: filtered.length),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
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
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state, required this.count});

  final LiveLogState state;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final (color, label) = switch (state.status) {
      LiveLogStatus.running =>
        (const Color(0xFF3DDC84), state.paused ? 'Paused' : 'Streaming'),
      LiveLogStatus.starting => (const Color(0xFFFFB900), 'Starting'),
      LiveLogStatus.stopped => (const Color(0xFF767676), 'Stopped'),
      LiveLogStatus.failure => (const Color(0xFFE81123), 'Error'),
      LiveLogStatus.idle => (const Color(0xFF767676), 'Idle'),
    };
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(state.paused ? 'Paused' : label,
            style: theme.typography.caption?.copyWith(color: color)),
        const SizedBox(width: 12),
        Text('$count lines',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorTertiary,
            )),
        if (state.errorMessage != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(state.errorMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.caption
                    ?.copyWith(color: const Color(0xFFE81123))),
          ),
        ],
      ],
    );
  }
}

class _NoDevices extends StatelessWidget {
  const _NoDevices({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.plug_disconnected,
              size: 44, color: theme.resources.textFillColorTertiary),
          const SizedBox(height: 14),
          Text('No online devices', style: theme.typography.subtitle),
          const SizedBox(height: 8),
          Text('Connect a device or start an emulator, then refresh.',
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorSecondary,
              )),
          const SizedBox(height: 18),
          FilledButton(onPressed: onRefresh, child: const Text('Refresh')),
        ],
      ),
    );
  }
}
