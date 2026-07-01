import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/settings/app_settings.dart';
import '../../application/settings/settings_cubit.dart';
import '../../core/di/injection.dart';
import 'dev_logs_page.dart';

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
                            onPressed: () => Navigator.of(context).push(
                              FluentPageRoute<void>(
                                  builder: (_) => const DevLogsPage()),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.text_document, size: 14),
                                SizedBox(width: 8),
                                Text('Open request log'),
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
