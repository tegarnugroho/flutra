import 'package:fluent_ui/fluent_ui.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../domain/entities/jdk.dart';
import '../../common/copy_icon_button.dart';
import '../../common/outlined_action_button.dart';
import '../../common/status_pill.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The panel that answers "which JDK do my builds get, and who decided that".
///
/// Same highlighted surface as the Flutter SDK page's header: the version is
/// the page's subject, the list below it is the alternatives.
class JavaIdentityPanel extends StatelessWidget {
  const JavaIdentityPanel({
    super.key,
    required this.active,
    required this.configuredForFlutter,
    required this.busy,
    required this.onSetForFlutter,
    required this.onInstall,
  });

  /// The JDK in force, or null when nothing usable was found.
  final ActiveJdk? active;

  /// Whether `flutter config --jdk-dir` names a JDK.
  final bool configuredForFlutter;

  final bool busy;

  /// Pins the active JDK for Flutter builds. Null when there is nothing to
  /// pin — an empty machine, or an entry that cannot be selected.
  final VoidCallback? onSetForFlutter;

  /// Opens the downloadable-JDK picker.
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised.withValues(alpha: 0.35),
        border: Border.all(
          color: palette.borderStrong,
          width: AppShape.hairline,
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: active == null
          ? _NoJdk(palette: palette, onInstall: onInstall)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Mark(palette: palette),
                const SizedBox(width: 14),
                Expanded(child: _identity(context, palette)),
                const SizedBox(width: 16),
                _FlutterStatus(
                  configured: configuredForFlutter,
                  busy: busy,
                  onSetForFlutter: onSetForFlutter,
                ),
              ],
            ),
    );
  }

  Widget _identity(BuildContext context, AppPalette palette) {
    final text = AppTextStyles.of(context);
    final jdk = active!.jdk;
    final source = active!.source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                jdk.displayName,
                style: text.heroVersion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            // Accent only for Flutter's own setting: it is the one that
            // survives a shell that exported nothing, and the one this page
            // can change.
            Flexible(
              child: StatusPill(
                label: source.label,
                foreground: source == ActiveJdkSource.flutterConfig
                    ? palette.accent
                    : palette.textMuted,
                background: source == ActiveJdkSource.flutterConfig
                    ? palette.accentBgTint
                    : palette.surfaceRaised,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _separated(context, [
            if (jdk.version != null) _meta(context, value: jdk.version!),
            if (jdk.vendor != null) _meta(context, value: jdk.vendor!),
            _meta(
              context,
              value: jdk.path,
              copyValue: jdk.path,
              copyLabel: 'JDK path',
            ),
          ]),
        ),
      ],
    );
  }

  /// Interleaves the fragments with a middle dot, inside the [Wrap]'s run so a
  /// separator wraps with the fragment it belongs to.
  List<Widget> _separated(BuildContext context, List<Widget> fragments) {
    final style = AppTextStyles.of(context).monoMeta;
    return [
      for (var i = 0; i < fragments.length; i++) ...[
        if (i > 0) Text('·', style: style),
        fragments[i],
      ],
    ];
  }

  Widget _meta(
    BuildContext context, {
    required String value,
    String? copyValue,
    String? copyLabel,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            value,
            style: AppTextStyles.of(context).monoMeta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (copyValue != null) ...[
          const SizedBox(width: 4),
          CopyIconButton(value: copyValue, label: copyLabel ?? 'Value'),
        ],
      ],
    );
  }
}

/// The Java mark in its rounded square.
class _Mark extends StatelessWidget {
  const _Mark({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.accentBgTint,
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: Icon(SimpleIcons.openjdk, size: 20, color: palette.accent),
    );
  }
}

/// Whether Flutter builds have been pinned to a JDK, and the way to pin them.
class _FlutterStatus extends StatelessWidget {
  const _FlutterStatus({
    required this.configured,
    required this.busy,
    required this.onSetForFlutter,
  });

  final bool configured;
  final bool busy;
  final VoidCallback? onSetForFlutter;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.of(context);

    if (configured) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.check_mark, size: 12, color: palette.textMuted),
          const SizedBox(width: 6),
          Text('Used by Flutter builds', style: text.caption),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        OutlinedActionButton(
          icon: FluentIcons.warning,
          label: busy ? 'Setting…' : 'Set for Flutter',
          warning: true,
          busy: busy,
          tooltip: 'Run "flutter config --jdk-dir" for this JDK',
          onPressed: busy ? null : onSetForFlutter,
        ),
        const SizedBox(height: 5),
        Text('Flutter is using system default', style: text.caption),
      ],
    );
  }
}

/// The panel when the machine has no JDK the app can see.
class _NoJdk extends StatelessWidget {
  const _NoJdk({required this.palette, required this.onInstall});

  final AppPalette palette;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Mark(palette: palette),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No JDK detected', style: text.heroTitle),
              const SizedBox(height: 6),
              Text(
                'Android builds need a JDK. Install one, or point the app at '
                'an existing install with "Add JDK…".',
                style: text.caption,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        OutlinedActionButton(
          icon: FluentIcons.download,
          label: 'Install JDK',
          warning: true,
          tooltip: 'Show the JDKs available to download',
          onPressed: onInstall,
        ),
      ],
    );
  }
}
