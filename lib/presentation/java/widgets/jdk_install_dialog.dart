import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../application/java/java_cubit.dart';
import '../../../domain/entities/jdk_release.dart';
import '../../../infrastructure/java/jdk_install_service.dart';
import '../../common/app_loader.dart';
import '../../common/compact_field.dart';
import '../../common/outlined_action_button.dart';
import '../../common/status_pill.dart';
import '../../common/tile_box.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The downloadable JDKs, one tile per feature version.
///
/// Opened from the page, which owns the cubit — the dialog reads the same one
/// so a catalogue fetched once is not fetched again on the second open.
Future<void> showJdkInstallDialog(BuildContext context, JavaCubit cubit) {
  cubit.loadCatalog();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BlocProvider.value(
      value: cubit,
      child: const _JdkInstallDialog(),
    ),
  );
}

class _JdkInstallDialog extends StatelessWidget {
  const _JdkInstallDialog();

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    return BlocBuilder<JavaCubit, JavaState>(
      builder: (context, state) {
        final cubit = context.read<JavaCubit>();
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
          title: Row(
            children: [
              Text('Install a JDK', style: text.heroTitle),
              const Spacer(),
              _SourcePicker(
                selected: state.catalogSource,
                servedBy: state.catalogVendor,
                onChanged: cubit.setCatalogSource,
              ),
            ],
          ),
          content: _body(context, state, cubit),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context, JavaState state, JavaCubit cubit) {
    final text = AppTextStyles.of(context);

    if (state.catalogStatus == CatalogStatus.loading && state.catalog.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: AppLoader()),
      );
    }

    if (state.catalog.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.catalogError ?? 'No downloads were offered.',
            style: text.caption,
          ),
          const SizedBox(height: 14),
          OutlinedActionButton(
            icon: FluentIcons.refresh,
            label: 'Try again',
            onPressed: () => cubit.loadCatalog(force: true),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Installs into this app\'s own folder — no elevation, and removing '
          'one is deleting a directory.',
          style: text.caption,
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: state.catalog.length,
            separatorBuilder: (_, _) => const SizedBox(height: TileBox.gap),
            itemBuilder: (context, i) {
              final release = state.catalog[i];
              return _ReleaseTile(
                release: release,
                install: state.installOf(release),
                installed: state.jdks.any(
                  (jdk) => jdk.version == release.version,
                ),
                onInstall: () => cubit.install(release),
                onCancel: () => cubit.cancelInstall(release),
                onDismiss: () => cubit.dismissInstall(release),
                onOpenInBrowser: () => cubit.openDownload(release),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Auto / Temurin / Zulu.
///
/// Auto is the default because the two catalogues hold the same OpenJDK; the
/// choice only matters when one API is down or someone has a house preference.
class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.selected,
    required this.servedBy,
    required this.onChanged,
  });

  final JdkVendor? selected;
  final JdkVendor? servedBy;
  final ValueChanged<JdkVendor?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // When the choice is Auto, say which one actually answered.
        if (selected == null && servedBy != null) ...[
          Text(servedBy!.label, style: text.caption),
          const SizedBox(width: 10),
        ],
        CompactCombo<String>(
          width: 150,
          value: selected?.name ?? 'auto',
          items: [
            const CompactComboItem(value: 'auto', label: 'Source: automatic'),
            for (final vendor in JdkVendor.values)
              CompactComboItem(value: vendor.name, label: vendor.label),
          ],
          onChanged: (value) => onChanged(
            value == 'auto'
                ? null
                : JdkVendor.values.firstWhere((v) => v.name == value),
          ),
        ),
      ],
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.release,
    required this.install,
    required this.installed,
    required this.onInstall,
    required this.onCancel,
    required this.onDismiss,
    required this.onOpenInBrowser,
  });

  final JdkRelease release;

  /// The install in flight for this release, or null.
  final JdkInstallEvent? install;

  /// True when a JDK of this exact version is already on the machine.
  final bool installed;

  final VoidCallback onInstall;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final VoidCallback onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);
    final size = release.displaySize;

    return TileBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(AppShape.radiusControl),
              ),
              child: Icon(
                SimpleIcons.openjdk,
                size: 15,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'JDK ${release.major}',
                          style: text.rowTitle.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (release.lts) ...[
                        const SizedBox(width: 8),
                        // The versions that keep getting security fixes — the
                        // ones worth defaulting to.
                        Flexible(
                          child: StatusPill(
                            label: 'LTS',
                            foreground: palette.statusOk,
                            background: palette.okSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [release.version, ?size, ?_stageNote].join(' · '),
                    style: text.monoMeta.copyWith(
                      fontSize: 11,
                      color: install?.stage == JdkInstallStage.failed
                          ? palette.statusError
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (install?.stage == JdkInstallStage.downloading) ...[
                    const SizedBox(height: 6),
                    ProgressBar(
                      value: install!.progress == null
                          ? null
                          : install!.progress! * 100,
                      activeColor: palette.accent,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ..._actions(context),
          ],
        ),
      ),
    );
  }

  /// The stage, or the reason it stopped.
  String? get _stageNote {
    final event = install;
    if (event == null) return installed ? 'already installed' : null;
    if (event.stage == JdkInstallStage.failed) return event.error;
    if (event.stage == JdkInstallStage.downloading) {
      final progress = event.progress;
      return progress == null
          ? event.stage.label
          : '${(progress * 100).round()}%';
    }
    return event.stage.label;
  }

  List<Widget> _actions(BuildContext context) {
    final event = install;

    if (event != null && event.stage == JdkInstallStage.failed) {
      return [
        OutlinedActionButton(
          icon: FluentIcons.refresh,
          label: 'Retry',
          dense: true,
          onPressed: () {
            onDismiss();
            onInstall();
          },
        ),
      ];
    }

    if (event != null) {
      return [
        OutlinedActionButton(
          icon: FluentIcons.cancel,
          label: 'Cancel',
          dense: true,
          dangerOnHover: true,
          onPressed: onCancel,
        ),
      ];
    }

    return [
      // The browser stays an option: 200 MB through someone else's download
      // manager is a reasonable preference, not a fallback.
      OutlinedActionButton(
        icon: FluentIcons.globe,
        dense: true,
        tooltip: 'Open the download in your browser',
        onPressed: onOpenInBrowser,
      ),
      const SizedBox(width: 6),
      OutlinedActionButton(
        icon: FluentIcons.download,
        label: installed ? 'Reinstall' : 'Install',
        dense: true,
        tooltip: release.fileName,
        onPressed: onInstall,
      ),
    ];
  }
}
