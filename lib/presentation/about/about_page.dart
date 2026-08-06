import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show LicensePage;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/flutter_sdk/flutter_update_cubit.dart';
import '../../core/constants/app_info.dart';
import '../../core/di/injection.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../../infrastructure/system/external_link_service.dart';
import '../common/app_loader.dart';
import '../common/copy_icon_button.dart';
import '../common/segmented_control.dart' show onAccent;
import '../common/task_window_title_bar.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// The About window's content: what this build is, and where to go from here.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FlutterUpdateCubit>(),
      child: _AboutView(onClose: onClose),
    );
  }
}

class _AboutView extends StatelessWidget {
  const _AboutView({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: FocusScope(
        autofocus: true,
        child: Column(
          children: [
            TaskWindowTitleBar(title: 'About', onClose: onClose),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  kTaskWindowInset,
                  18,
                  kTaskWindowInset,
                  18,
                ),
                child: Column(
                  children: [
                    const _AppIconTile(),
                    const SizedBox(height: 16),
                    Text(AppInfo.name, style: text.heroTitle),
                    const SizedBox(height: 6),
                    const _VersionLine(),
                    const SizedBox(height: 3),
                    Text(
                      '${AppInfo.channel} channel · ${AppInfo.platformLabel}',
                      style: text.caption,
                    ),
                    const SizedBox(height: 18),
                    const _EnvironmentCard(),
                    const SizedBox(height: 18),
                    _Actions(onClose: onClose),
                    const SizedBox(height: 16),
                    const _Links(),
                    const SizedBox(height: 14),
                    Text(AppInfo.copyright, style: text.caption),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The real app icon on an accent-tinted tile — a glyph here would look like a
/// placeholder in the one place the app introduces itself.
class _AppIconTile extends StatelessWidget {
  const _AppIconTile();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // The window is 400px wide and this is the one place the app introduces
    // itself, so the mark carries the header rather than sitting in it.
    const size = 96.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.accentBgTint,
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        // The source is 941px; decoding it small keeps the raster cache sane.
        // Three times the layout size stays sharp on a 200% display.
        cacheWidth: 288,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, _) =>
            Icon(FluentIcons.cell_phone, size: 44, color: palette.accent),
      ),
    );
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Version ${AppInfo.version} (build ${AppInfo.buildNumber})',
          style: text.statusLine,
        ),
        const SizedBox(width: 6),
        // Copies the whole diagnostic block, not the number — a version alone
        // answers almost none of the questions a bug report asks.
        CopyIconButton(value: AppInfo.diagnosticBlock(), label: 'Build info'),
      ],
    );
  }
}

class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard();

  /// The Flutter version, preferring what the build was told.
  ///
  /// Without a define there is nothing to read from the framework itself, so
  /// this falls back to the SDK the app manages — on a developer's machine
  /// that is the same checkout, and it beats showing a dash.
  Future<String> _flutterVersion() async {
    if (AppInfo.flutterVersion != AppInfo.unknown) {
      return AppInfo.flutterVersion;
    }
    try {
      final info = await getIt<FlutterRepository>().getSdkInfo();
      return info.version;
    } catch (_) {
      return AppInfo.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.logBg,
        border: Border.all(color: palette.border, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: Column(
        children: [
          FutureBuilder<String>(
            future: _flutterVersion(),
            builder: (context, snapshot) =>
                _EnvRow(label: 'Flutter', value: snapshot.data ?? '…'),
          ),
          const SizedBox(height: 7),
          _EnvRow(label: 'Dart', value: AppInfo.dartVersion),
          const SizedBox(height: 7),
          _EnvRow(
            label: 'Commit',
            value: AppInfo.commit,
            // Only a build can know this; a dev run has nothing to report.
            hint: AppInfo.commit == AppInfo.unknown
                ? 'Set at build time via --dart-define=APP_COMMIT'
                : null,
          ),
        ],
      ),
    );
  }
}

class _EnvRow extends StatelessWidget {
  const _EnvRow({required this.label, required this.value, this.hint});

  final String label;
  final String value;

  /// Explains an absent value on hover, rather than leaving a bare dash.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return Row(
      children: [
        Text(label, style: text.rowLabel),
        const Spacer(),
        hint == null
            ? Text(value, style: text.monoValue)
            : Tooltip(
                message: hint!,
                child: Text(value, style: text.monoValue),
              ),
      ],
    );
  }
}

/// Update check and licences.
class _Actions extends StatelessWidget {
  const _Actions({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _UpdateButton()),
        const SizedBox(width: 10),
        Expanded(
          child: _AboutButton(
            icon: FluentIcons.certificate,
            label: 'Licenses',
            onPressed: () => _openLicenses(context),
          ),
        ),
      ],
    );
  }

  /// Flutter's own licence registry, themed and pushed onto this window's
  /// navigator — a third OS window for a list of licences would be absurd.
  void _openLicenses(BuildContext context) {
    Navigator.of(context).push(
      FluentPageRoute<void>(
        builder: (context) => LicensePage(
          applicationName: AppInfo.name,
          applicationVersion:
              'Version ${AppInfo.version} (build ${AppInfo.buildNumber})',
          applicationLegalese: AppInfo.copyright,
        ),
      ),
    );
  }
}

/// Runs the existing Flutter-update check and reports the outcome in place.
class _UpdateButton extends StatelessWidget {
  const _UpdateButton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    return BlocBuilder<FlutterUpdateCubit, FlutterUpdateState>(
      builder: (context, state) {
        final cubit = context.read<FlutterUpdateCubit>();
        final checking = state.status == FlutterUpdateCheckStatus.loading;

        if (checking) {
          return _AboutButton(
            primary: true,
            leading: AppLoader(
              size: AppLoaderSize.small,
              color: onAccent(palette),
            ),
            label: 'Checking…',
            onPressed: null,
          );
        }
        if (state.update?.updateAvailable ?? false) {
          // This window can't drive the main window's navigation, so it names
          // the release and leaves the install to the Updates screen.
          return _AboutButton(
            primary: true,
            icon: FluentIcons.download,
            label: 'Update available',
            tooltip:
                'Open Updates in the main window to install '
                        '${state.update?.latest?.version ?? ''}'
                    .trim(),
            onPressed: () => cubit.check(forceRefresh: true),
          );
        }
        if (state.status == FlutterUpdateCheckStatus.ready) {
          return _AboutButton(
            icon: FluentIcons.completed_solid,
            label: 'Up to date',
            foreground: palette.statusOk,
            onPressed: () => cubit.check(forceRefresh: true),
          );
        }
        return _AboutButton(
          primary: true,
          icon: FluentIcons.sync,
          label: 'Check for updates',
          onPressed: cubit.check,
          subtitleStyle: text.caption,
        );
      },
    );
  }
}

/// The two action buttons share one shape; primary is accent-filled.
class _AboutButton extends StatefulWidget {
  const _AboutButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.primary = false,
    this.foreground,
    this.tooltip,
    this.subtitleStyle,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final bool primary;
  final Color? foreground;
  final String? tooltip;
  final TextStyle? subtitleStyle;

  @override
  State<_AboutButton> createState() => _AboutButtonState();
}

class _AboutButtonState extends State<_AboutButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final enabled = widget.onPressed != null;

    final foreground =
        widget.foreground ??
        (widget.primary ? onAccent(palette) : palette.textTertiary);

    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.primary
                ? (_hovered && enabled
                      ? Color.alphaBlend(
                          palette.textPrimary.withValues(alpha: 0.12),
                          palette.accent,
                        )
                      : palette.accent)
                : (_hovered && enabled
                      ? palette.surfaceRaised
                      : Colors.transparent),
            border: widget.primary
                ? null
                : Border.all(
                    color: palette.borderStrong,
                    width: AppShape.hairline,
                  ),
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.leading != null)
                widget.leading!
              else if (widget.icon != null)
                Icon(widget.icon, size: 13, color: foreground),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: text.buttonLabel.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

class _Links extends StatelessWidget {
  const _Links();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Link(
          icon: FluentIcons.git_graph,
          label: 'GitHub',
          url: AppInfo.repositoryUrl,
        ),
        SizedBox(width: 14),
        _Link(
          icon: FluentIcons.bug,
          label: 'Report an issue',
          url: AppInfo.issuesUrl,
        ),
        SizedBox(width: 14),
        _Link(
          icon: FluentIcons.text_document,
          label: 'Release notes',
          url: AppInfo.releaseNotesUrl,
        ),
      ],
    );
  }
}

class _Link extends StatefulWidget {
  const _Link({required this.icon, required this.label, required this.url});

  final IconData icon;
  final String label;
  final String url;

  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => getIt<ExternalLinkService>().open(widget.url),
        child: Tooltip(
          message: widget.url,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 11,
                color: _hovered ? palette.accent : palette.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: text.caption.copyWith(
                  color: _hovered ? palette.accent : palette.textSecondary,
                  decoration: _hovered ? TextDecoration.underline : null,
                  decorationColor: palette.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
