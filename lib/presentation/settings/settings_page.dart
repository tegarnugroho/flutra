import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../application/address/address_cubit.dart';
import '../../application/settings/app_settings.dart';
import '../../application/settings/settings_cubit.dart';
import '../../application/settings/theme_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/address.dart';
import '../../infrastructure/system/process_service.dart';
import '../../main.dart' show kDevLogsWindow;
import '../emulator/widgets/avd_dialogs.dart';

/// Settings: theme, Android SDK path override and run-at-startup.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: getIt<SettingsCubit>(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return ScaffoldPage(
      header: const PageHeader(title: Text('Settings')),
      content: BlocBuilder<SettingsCubit, AppSettings>(
        builder: (context, settings) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  title: 'Appearance',
                  child: _Setting(
                    icon: FluentIcons.color,
                    title: 'Theme',
                    subtitle: 'Choose light, dark, or follow the system.',
                    trailing: SizedBox(
                      width: 160,
                      child: ComboBox<ThemeMode>(
                        isExpanded: true,
                        value: settings.themeMode,
                        items: const [
                          ComboBoxItem(
                              value: ThemeMode.system, child: Text('System')),
                          ComboBoxItem(
                              value: ThemeMode.light, child: Text('Light')),
                          ComboBoxItem(
                              value: ThemeMode.dark, child: Text('Dark')),
                        ],
                        onChanged: (v) =>
                            v == null ? null : cubit.setThemeMode(v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Android SDK',
                  child: _PathSetting(
                    label: 'Android SDK path',
                    description: 'Override the auto-detected SDK location. '
                        'Leave empty to auto-detect.',
                    placeholder:
                        r'e.g. C:\Users\you\AppData\Local\Android\Sdk',
                    path: settings.androidSdkPath,
                    onApply: cubit.setAndroidSdkPath,
                  ),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Flutter SDK',
                  child: _PathSetting(
                    label: 'Flutter SDK path',
                    description: 'Point at a specific Flutter checkout. Leave '
                        'empty to use the one on your PATH.',
                    placeholder: r'e.g. C:\Dev\SDK\flutter',
                    path: settings.flutterSdkPath,
                    onApply: cubit.setFlutterSdkPath,
                  ),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'API',
                  child: _PathSetting(
                    label: 'API base URL',
                    description: 'Base URL for the settings API '
                        '(addresses are fetched from '
                        '"<base>/api/settings/addresses").',
                    placeholder: 'e.g. https://api.example.com',
                    path: settings.apiBaseUrl,
                    onApply: cubit.setApiBaseUrl,
                  ),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Addresses',
                  child: _AddressesSection(
                    hasBaseUrl: settings.apiBaseUrl != null,
                  ),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'System',
                  child: Column(
                    children: [
                      _Setting(
                        icon: FluentIcons.power_button,
                        title: 'Run at startup',
                        subtitle: 'Launch Flutter SDK Manager when you sign in '
                            'to Windows.',
                        trailing: ToggleSwitch(
                          checked: settings.runAtStartup,
                          onChanged: cubit.setRunAtStartup,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Setting(
                        icon: FluentIcons.chrome_minimize,
                        title: 'Close to system tray',
                        subtitle: 'Hide to the tray on close instead of '
                            'quitting. Right-click the tray icon to exit.',
                        trailing: ToggleSwitch(
                          checked: settings.closeToTray,
                          onChanged: cubit.setCloseToTray,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Setting(
                        icon: FluentIcons.blocked2,
                        title: 'Stop all Flutter & Dart processes',
                        subtitle: 'Force-kills every running dart/flutter '
                            'process — frees a locked SDK (also stops the IDE '
                            'analyzer).',
                        trailing: Button(
                          onPressed: () => _stopProcesses(context),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.blocked2,
                                  size: 14, color: Color(0xFFC42B1C)),
                              SizedBox(width: 6),
                              Text('Stop all'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Developer',
                  child: Column(
                    children: [
                      _Setting(
                        icon: FluentIcons.developer_tools,
                        title: 'Developer mode',
                        subtitle: 'Capture every command/request in an in-app '
                            'log viewer for debugging.',
                        trailing: ToggleSwitch(
                          checked: settings.developerMode,
                          onChanged: cubit.setDeveloperMode,
                        ),
                      ),
                      if (settings.developerMode) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Button(
                            onPressed: _openDevLogsWindow,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.text_document, size: 14),
                                SizedBox(width: 8),
                                Text('Open request log (new window)'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Confirms, then force-kills all Flutter/Dart processes.
Future<void> _stopProcesses(BuildContext context) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Stop all Flutter & Dart processes?',
    message: 'This force-kills every running dart/flutter process, including '
        'your IDE\'s analysis server. Use it to free a locked SDK.',
    confirmLabel: 'Stop all',
  );
  if (!ok || !context.mounted) return;
  final killed = await getIt<ProcessService>().stopFlutterAndDart();
  if (!context.mounted) return;
  await displayInfoBar(context, builder: (context, close) {
    return InfoBar(
      title: Text(killed > 0 ? 'Stopped $killed process(es)' : 'Nothing running'),
      content: Text(killed > 0
          ? 'All Flutter/Dart processes were terminated.'
          : 'No Flutter/Dart processes were running.'),
      severity: killed > 0 ? InfoBarSeverity.success : InfoBarSeverity.info,
      onClose: close,
    );
  });
}

/// Fetches and lists addresses from the settings API.
class _AddressesSection extends StatelessWidget {
  const _AddressesSection({required this.hasBaseUrl});

  final bool hasBaseUrl;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<AddressCubit>(),
      child: Builder(
        builder: (context) {
          final cubit = context.read<AddressCubit>();
          final theme = FluentTheme.of(context);
          return BlocBuilder<AddressCubit, AddressState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(FluentIcons.location, size: 18,
                          color: theme.accentColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Saved addresses',
                            style: theme.typography.bodyStrong),
                      ),
                      Button(
                        onPressed: !hasBaseUrl || state.isLoading
                            ? null
                            : cubit.load,
                        child: state.isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: ProgressRing(strokeWidth: 2))
                            : const Text('Load'),
                      ),
                    ],
                  ),
                  if (!hasBaseUrl)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Set the API base URL above first.',
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorTertiary,
                          )),
                    )
                  else if (state.status == AddressStatus.failure)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: InfoBar(
                        title: const Text('Could not load addresses'),
                        content: Text(state.errorMessage ?? 'Unknown error.'),
                        severity: InfoBarSeverity.error,
                        isLong: true,
                      ),
                    )
                  else if (state.addresses.isEmpty &&
                      state.status == AddressStatus.ready)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('No addresses.',
                          style: theme.typography.caption),
                    )
                  else
                    for (final a in state.addresses)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _AddressTile(address: a),
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.address});

  final Address address;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(address.label, style: theme.typography.bodyStrong),
              const SizedBox(width: 8),
              _pill(theme, address.type, const Color(0xFF54C5F8)),
              if (address.isDefault) ...[
                const SizedBox(width: 6),
                _pill(theme, 'Default', const Color(0xFF3DDC84)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(address.formatted,
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              )),
        ],
      ),
    );
  }

  Widget _pill(FluentThemeData theme, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11, color: color)),
      );
}

/// Opens the Developer Logs as a separate OS window.
Future<void> _openDevLogsWindow() async {
  final dark = getIt<ThemeCubit>().state == ThemeMode.dark;
  await WindowController.create(WindowConfiguration(
    arguments: jsonEncode({'businessId': kDevLogsWindow, 'dark': dark}),
    hiddenAtLaunch: false,
  ));
}

class _PathSetting extends StatefulWidget {
  const _PathSetting({
    required this.label,
    required this.description,
    required this.placeholder,
    required this.path,
    required this.onApply,
  });

  final String label;
  final String description;
  final String placeholder;
  final String? path;
  final ValueChanged<String> onApply;

  @override
  State<_PathSetting> createState() => _PathSettingState();
}

class _PathSettingState extends State<_PathSetting> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.path ?? '');
  }

  @override
  void didUpdateWidget(covariant _PathSetting old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path && (widget.path ?? '') != _controller.text) {
      _controller.text = widget.path ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(FluentIcons.folder_open, size: 18, color: theme.accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: theme.typography.bodyStrong),
                  Text(
                    widget.description,
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextBox(
                controller: _controller,
                placeholder: widget.placeholder,
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => widget.onApply(_controller.text),
              child: const Text('Apply'),
            ),
            const SizedBox(width: 6),
            Button(
              onPressed: () {
                _controller.clear();
                widget.onApply('');
              },
              child: const Text('Auto'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.typography.subtitle),
        const SizedBox(height: 10),
        Card(padding: const EdgeInsets.all(16), child: child),
      ],
    );
  }
}

class _Setting extends StatelessWidget {
  const _Setting({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.accentColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.typography.bodyStrong),
              Text(subtitle,
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  )),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }
}
