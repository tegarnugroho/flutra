import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/address/address_cubit.dart';
import '../../application/settings/app_settings.dart';
import '../../application/settings/settings_cubit.dart';
import '../../application/settings/theme_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/address.dart';
import '../../infrastructure/system/process_service.dart';
import '../../main.dart' show kDevLogsWindow;
import '../common/app_badge.dart';
import '../common/compact_field.dart';
import '../common/confirm_dialog.dart';
import '../common/grouped_list.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Settings: theme, SDK path overrides, behaviour and developer tools.
///
/// Every control applies immediately — there is no save step.
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
    return PageScaffold(
      title: 'Settings',
      child: BlocBuilder<SettingsCubit, AppSettings>(
        builder: (context, settings) {
          return SingleChildScrollView(
            padding: kPageBodyPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('General'),
                const SizedBox(height: 8),
                GroupedList(
                  children: [
                    GroupedListRow(
                      title: 'Theme',
                      subtitle: 'Choose light, dark, or follow the system.',
                      trailing: [
                        CompactCombo<ThemeMode>(
                          width: 130,
                          value: settings.themeMode,
                          items: const [
                            CompactComboItem(
                                value: ThemeMode.system, label: 'System'),
                            CompactComboItem(
                                value: ThemeMode.light, label: 'Light'),
                            CompactComboItem(
                                value: ThemeMode.dark, label: 'Dark'),
                          ],
                          onChanged: cubit.setThemeMode,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionLabel('Paths'),
                const SizedBox(height: 8),
                GroupedList(
                  children: [
                    _PathSetting(
                      label: 'Android SDK',
                      description: 'Override the auto-detected SDK location. '
                          'Leave empty to auto-detect.',
                      placeholder:
                          r'e.g. C:\Users\you\AppData\Local\Android\Sdk',
                      path: settings.androidSdkPath,
                      onApply: cubit.setAndroidSdkPath,
                    ),
                    _PathSetting(
                      label: 'Flutter SDK',
                      description: 'Point at a specific Flutter checkout. '
                          'Leave empty to use the one on your PATH.',
                      placeholder: r'e.g. C:\Dev\SDK\flutter',
                      path: settings.flutterSdkPath,
                      onApply: cubit.setFlutterSdkPath,
                    ),
                    _PathSetting(
                      label: 'API base URL',
                      description: 'Base URL for the settings API — addresses '
                          'come from "<base>/api/settings/addresses".',
                      placeholder: 'e.g. https://api.example.com',
                      path: settings.apiBaseUrl,
                      onApply: cubit.setApiBaseUrl,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionLabel('Behaviour'),
                const SizedBox(height: 8),
                GroupedList(
                  children: [
                    GroupedListRow(
                      title: 'Run at startup',
                      subtitle: 'Launch Flutter SDK Manager when you sign in '
                          'to Windows.',
                      trailing: [
                        AppToggle(
                          checked: settings.runAtStartup,
                          onChanged: cubit.setRunAtStartup,
                        ),
                      ],
                    ),
                    GroupedListRow(
                      title: 'Close to system tray',
                      subtitle: 'Hide to the tray on close instead of '
                          'quitting. Right-click the tray icon to exit.',
                      trailing: [
                        AppToggle(
                          checked: settings.closeToTray,
                          onChanged: cubit.setCloseToTray,
                        ),
                      ],
                    ),
                    GroupedListRow(
                      title: 'Stop all Flutter and Dart processes',
                      subtitle: 'Force-kills every running dart/flutter '
                          'process — frees a locked SDK (also stops the IDE '
                          'analyzer).',
                      trailing: [
                        OutlinedActionButton(
                          icon: FluentIcons.blocked2,
                          label: 'Stop all',
                          dense: true,
                          onPressed: () => _stopProcesses(context),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionLabel('Developer'),
                const SizedBox(height: 8),
                GroupedList(
                  children: [
                    GroupedListRow(
                      title: 'Developer mode',
                      subtitle: 'Capture every command/request in an in-app '
                          'log viewer for debugging.',
                      trailing: [
                        AppToggle(
                          checked: settings.developerMode,
                          onChanged: cubit.setDeveloperMode,
                        ),
                      ],
                    ),
                    if (settings.developerMode)
                      GroupedListRow(
                        title: 'Request log',
                        subtitle: 'Opens the captured command and request log '
                            'in its own window.',
                        trailing: [
                          OutlinedActionButton(
                            icon: FluentIcons.text_document,
                            label: 'Open log',
                            dense: true,
                            onPressed: _openDevLogsWindow,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionLabel('Addresses'),
                const SizedBox(height: 8),
                _AddressesSection(hasBaseUrl: settings.apiBaseUrl != null),
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
    title: 'Stop all Flutter and Dart processes?',
    message: 'This force-kills every running dart/flutter process, including '
        "your IDE's analysis server. Use it to free a locked SDK.",
    confirmLabel: 'Stop all',
  );
  if (!ok || !context.mounted) return;
  final killed = await getIt<ProcessService>().stopFlutterAndDart();
  if (!context.mounted) return;
  await displayInfoBar(context, builder: (context, close) {
    return InfoBar(
      title:
          Text(killed > 0 ? 'Stopped $killed process(es)' : 'Nothing running'),
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
          return BlocBuilder<AddressCubit, AddressState>(
            builder: (context, state) {
              return GroupedList(
                children: [
                  GroupedListRow(
                    icon: FluentIcons.location,
                    title: 'Saved addresses',
                    subtitle: hasBaseUrl
                        ? 'Fetched from the settings API.'
                        : 'Set the API base URL above first.',
                    trailing: [
                      if (state.isLoading)
                        const SizedBox(
                            width: 14,
                            height: 14,
                            child: ProgressRing(strokeWidth: 2))
                      else
                        OutlinedActionButton(
                          icon: FluentIcons.download,
                          label: 'Load',
                          dense: true,
                          onPressed: hasBaseUrl ? cubit.load : null,
                        ),
                    ],
                  ),
                  if (state.status == AddressStatus.failure)
                    GroupedListRow(
                      statusColor: AppColors.statusError,
                      showStatusSlot: true,
                      title: 'Could not load addresses',
                      subtitle: state.errorMessage ?? 'Unknown error.',
                    )
                  else if (state.addresses.isEmpty &&
                      state.status == AddressStatus.ready)
                    const GroupedListRow(title: 'No addresses')
                  else
                    for (final a in state.addresses) _AddressRow(address: a),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address});

  final Address address;

  @override
  Widget build(BuildContext context) {
    return GroupedListRow(
      titleWidget: Row(
        children: [
          Flexible(
            child: Text(address.label,
                style: AppTextStyles.rowTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          AppBadge(address.type),
          if (address.isDefault) ...[
            const SizedBox(width: 6),
            const AppBadge('default'),
          ],
        ],
      ),
      subtitle: address.formatted,
    );
  }
}

/// Opens the Developer Logs as a separate OS window.
Future<void> _openDevLogsWindow() async {
  final dark = getIt<ThemeCubit>().state == ThemeMode.dark;
  await WindowController.create(WindowConfiguration(
    arguments: jsonEncode({'businessId': kDevLogsWindow, 'dark': dark}),
    hiddenAtLaunch: false,
  ));
}

/// A path override: description, editable value and apply/auto actions.
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
    return GroupedListRow(
      title: widget.label,
      subtitle: widget.description,
      below: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: CompactField(
                controller: _controller,
                icon: FluentIcons.folder_open,
                placeholder: widget.placeholder,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedActionButton(
              icon: FluentIcons.check_mark,
              label: 'Apply',
              dense: true,
              onPressed: () => widget.onApply(_controller.text),
            ),
            const SizedBox(width: 8),
            OutlinedActionButton(
              icon: FluentIcons.reset,
              label: 'Auto',
              dense: true,
              onPressed: () {
                _controller.clear();
                widget.onApply('');
              },
            ),
          ],
        ),
      ),
    );
  }
}
