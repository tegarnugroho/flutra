import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/log/live_log_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/avd.dart';
import '../../domain/entities/avd_create_request.dart';
import '../../domain/repositories/emulator_repository.dart';
import '../common/live_log_view.dart';
import '../common/log_toolbar.dart';

/// Emulator Console: launches an AVD and streams its stdout/stderr live.
class EmulatorConsolePage extends StatefulWidget {
  const EmulatorConsolePage({super.key});

  @override
  State<EmulatorConsolePage> createState() => _EmulatorConsolePageState();
}

class _EmulatorConsolePageState extends State<EmulatorConsolePage> {
  final EmulatorRepository _emulators = getIt<EmulatorRepository>();
  final LiveLogCubit _cubit = LiveLogCubit(parseLogcat: false);

  List<Avd> _avds = const [];
  String? _name;
  bool _loading = false;
  bool _coldBoot = false;

  @override
  void initState() {
    super.initState();
    _loadAvds();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _loadAvds() async {
    setState(() => _loading = true);
    try {
      final avds = await _emulators.listAvds();
      if (!mounted) return;
      setState(() {
        _avds = avds;
        _name ??= avds.isNotEmpty ? avds.first.name : null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _launch() {
    final name = _name;
    if (name == null) return;
    _cubit.start(() => _emulators.launch(
          name,
          LaunchOptions(coldBoot: _coldBoot, verbose: true),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: ScaffoldPage(
        header: PageHeader(
          title: const Text('Emulator Console'),
          commandBar: CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2))
                    : const Icon(FluentIcons.refresh),
                label: const Text('AVDs'),
                onPressed: _loading ? null : _loadAvds,
              ),
            ],
          ),
        ),
        content: _avds.isEmpty && !_loading
            ? _NoAvds(onRefresh: _loadAvds)
            : BlocBuilder<LiveLogCubit, LiveLogState>(
                builder: (context, state) {
                  final running = state.isRunning || state.isStarting;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 220,
                              child: ComboBox<String>(
                                isExpanded: true,
                                placeholder: const Text('Select AVD'),
                                value: _name,
                                items: [
                                  for (final a in _avds)
                                    ComboBoxItem(
                                        value: a.name, child: Text(a.name)),
                                ],
                                onChanged: running
                                    ? null
                                    : (v) => setState(() => _name = v),
                              ),
                            ),
                            Checkbox(
                              checked: _coldBoot,
                              onChanged: running
                                  ? null
                                  : (v) =>
                                      setState(() => _coldBoot = v ?? false),
                              content: const Text('Cold boot'),
                            ),
                            if (running)
                              FilledButton(
                                onPressed: () => _cubit.stop(),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(FluentIcons.stop, size: 12),
                                    SizedBox(width: 6),
                                    Text('Stop'),
                                  ],
                                ),
                              )
                            else
                              FilledButton(
                                onPressed: _name == null ? null : _launch,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(FluentIcons.play_solid, size: 12),
                                    SizedBox(width: 6),
                                    Text('Launch'),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                        child: LogToolbar(
                          cubit: _cubit,
                          state: state,
                          savePrefix: 'emulator',
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                          child: LiveLogView(
                            lines: state.filtered,
                            emptyHint: state.isStarting
                                ? 'Launching emulator…'
                                : 'Select an AVD and press Launch to see its '
                                    'console output.',
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

class _NoAvds extends StatelessWidget {
  const _NoAvds({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.cell_phone,
              size: 44, color: theme.resources.textFillColorTertiary),
          const SizedBox(height: 14),
          Text('No emulators', style: theme.typography.subtitle),
          const SizedBox(height: 8),
          Text('Create an AVD in the Emulator Manager first.',
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
