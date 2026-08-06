
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/address/address_cubit.dart';
import '../../application/settings/app_settings.dart';
import '../../application/settings/detected_paths_cubit.dart';
import '../../application/settings/settings_cubit.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/address.dart';
import '../../infrastructure/sdk/sdk_scan_service.dart';
import '../../infrastructure/system/process_service.dart';
import '../common/app_badge.dart';
import '../common/app_loader.dart';
import '../common/compact_field.dart';
import '../common/confirm_dialog.dart';
import '../common/copy_icon_button.dart';
import '../common/grouped_list.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../common/segmented_control.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../window/task_windows.dart';
import 'widgets/path_setting_row.dart';

/// Settings: theme, SDK path overrides, behaviour and developer tools.
///
/// Every control applies immediately — there is no save step.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: getIt<SettingsCubit>()),
        BlocProvider(create: (_) => getIt<DetectedPathsCubit>()..detect()),
      ],
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatefulWidget {
  const _SettingsView();

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  /// The row currently in edit state, if any. Held here rather than in the rows
  /// so opening one closes the other — two half-finished paths on screen is
  /// exactly the confusion this redesign removes.
  PathKind? _editing;

  void _beginEdit(PathKind kind) => setState(() => _editing = kind);
  void _endEdit() => setState(() => _editing = null);

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return PageScaffold(
      title: 'Settings',
      child: BlocBuilder<SettingsCubit, AppSettings>(
        builder: (context, settings) {
          return SingleChildScrollView(
            padding: kPageBodyPadding,
            child: ConstrainedBox(
              // The form reads as a column, not a full-width table.
              constraints: const BoxConstraints(maxWidth: 760),
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
                          SegmentedControl<ThemeMode>(
                            selected: settings.themeMode,
                            segments: const [
                              Segment(value: ThemeMode.light, label: 'Light'),
                              Segment(value: ThemeMode.dark, label: 'Dark'),
                              Segment(value: ThemeMode.system, label: 'System'),
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
                  BlocBuilder<DetectedPathsCubit, DetectedPathsState>(
                    builder: (context, detected) {
                      return Column(
                        children: [
                          PathSettingRow(
                            label: 'Android SDK',
                            description:
                                'Where the Android tools are read from.',
                            kind: PathKind.androidSdk,
                            overridePath: settings.androidSdkPath,
                            detected: detected.androidSdk,
                            loading: detected.isLoading,
                            onApply: cubit.setAndroidSdkPath,
                            editing: _editing == PathKind.androidSdk,
                            onBeginEdit: () => _beginEdit(PathKind.androidSdk),
                            onEndEdit: _endEdit,
                            scanning: detected.isScanning,
                            onScan: () => context
                                .read<DetectedPathsCubit>()
                                .scanFor(SdkScanKind.android),
                          ),
                          const SizedBox(height: 8),
                          PathSettingRow(
                            label: 'Flutter SDK',
                            description:
                                'Which Flutter checkout the app drives.',
                            kind: PathKind.flutterSdk,
                            overridePath: settings.flutterSdkPath,
                            detected: detected.flutter,
                            loading: detected.isLoading,
                            onApply: cubit.setFlutterSdkPath,
                            editing: _editing == PathKind.flutterSdk,
                            onBeginEdit: () => _beginEdit(PathKind.flutterSdk),
                            onEndEdit: _endEdit,
                            scanning: detected.isScanning,
                            onScan: () => context
                                .read<DetectedPathsCubit>()
                                .scanFor(SdkScanKind.flutter),
                          ),
                          const SizedBox(height: 8),
                          // Java has no override — it is read from JAVA_HOME or
                          // PATH — so this row only reports where it was found.
                          _ResolvedPathRow(
                            label: 'Java',
                            path: detected.java,
                            loading: detected.isLoading,
                          ),
                          const SizedBox(height: 8),
                          PathSettingRow(
                            label: 'API base URL',
                            description:
                                'Addresses come from '
                                '"<base>/api/settings/addresses".',
                            kind: PathKind.url,
                            overridePath: settings.apiBaseUrl,
                            detected: null,
                            onApply: cubit.setApiBaseUrl,
                            editing: _editing == PathKind.url,
                            onBeginEdit: () => _beginEdit(PathKind.url),
                            onEndEdit: _endEdit,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Behaviour'),
                  const SizedBox(height: 8),
                  GroupedList(
                    children: [
                      GroupedListRow(
                        title: 'Run at startup',
                        subtitle:
                            'Launch Flutter SDK Manager when you sign in '
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
                        subtitle:
                            'Hide to the tray on close instead of '
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
                        subtitle:
                            'Force-kills every running dart/flutter '
                            'process — frees a locked SDK (also stops the IDE '
                            'analyzer).',
                        trailing: [
                          OutlinedActionButton(
                            icon: FluentIcons.blocked2,
                            label: 'Stop all',
                            dense: true,
                            danger: true,
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
                        subtitle:
                            'Capture every command/request in an in-app '
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
                          subtitle:
                              'Opens the captured command and request log '
                              'in its own window.',
                          trailing: [
                            OutlinedActionButton(
                              icon: FluentIcons.text_document,
                              label: 'Open log',
                              dense: true,
                              onPressed: openDevLogsWindow,
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
    message:
        'This force-kills every running dart/flutter process, including '
        "other IDEs' analyzers. Continue?",
    confirmLabel: 'Stop all',
  );
  if (!ok || !context.mounted) return;
  final killed = await getIt<ProcessService>().stopFlutterAndDart();
  if (!context.mounted) return;
  await displayInfoBar(
    context,
    builder: (context, close) {
      return InfoBar(
        title: Text(
          killed > 0 ? 'Stopped $killed process(es)' : 'Nothing running',
        ),
        content: Text(
          killed > 0
              ? 'All Flutter/Dart processes were terminated.'
              : 'No Flutter/Dart processes were running.',
        ),
        severity: killed > 0 ? InfoBarSeverity.success : InfoBarSeverity.info,
        onClose: close,
      );
    },
  );
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
                        AppLoader(size: AppLoaderSize.small)
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
                      statusColor: AppPalette.of(context).statusError,
                      showStatusSlot: true,
                      title: 'Could not load addresses',
                      subtitle: state.errorMessage ?? 'Unknown error.',
                    )
                  else if (state.isLoading && state.addresses.isEmpty)
                    const AddressListSkeleton()
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
            child: Text(
              address.label,
              style: AppTextStyles.of(context).rowTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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

/// A path override: description, editable value and apply/auto actions.
/// The resolved location of a tool: ellipsized mono path plus copy.
///
/// Same row anatomy as the Paths list that used to sit on the Dashboard.
class _PathValue extends StatelessWidget {
  const _PathValue({required this.path, this.loading = false});

  static const _maxWidth = 300.0;

  final String? path;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final value = path;
    if (value == null || value.isEmpty) {
      return Text(
        // A quiet ellipsis while resolving, an em dash when there is nothing.
        loading ? '\u2026' : '\u2014',
        style: AppTextStyles.of(
          context,
        ).monoPath.copyWith(color: palette.textMuted),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Text(
            value,
            style: AppTextStyles.of(context).monoPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        CopyIconButton(value: value, label: 'Path'),
      ],
    );
  }
}

/// A path the app only reports — there is no override to edit.
class _ResolvedPathRow extends StatelessWidget {
  const _ResolvedPathRow({
    required this.label,
    required this.path,
    this.loading = false,
  });

  final String label;
  final String? path;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GroupedListRow(
      title: label,
      subtitle: 'Detected from JAVA_HOME, or from PATH when that is unset.',
      trailing: [_PathValue(path: path, loading: loading)],
    );
  }
}
