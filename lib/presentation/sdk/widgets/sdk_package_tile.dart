import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/sdk_package.dart';

/// A single SDK package row with version, status and install/uninstall action.
class SdkPackageTile extends StatelessWidget {
  const SdkPackageTile({
    super.key,
    required this.package,
    required this.onInstall,
    required this.onUninstall,
  });

  final SdkPackage package;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Card(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _statusDot(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.description,
                  style: theme.typography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  package.path,
                  style: theme.typography.caption?.copyWith(
                    fontFamily: 'Consolas',
                    color: theme.resources.textFillColorTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _versionColumn(theme),
          const SizedBox(width: 16),
          _action(theme),
        ],
      ),
    );
  }

  Widget _statusDot() {
    final color = switch (package.state) {
      PackageState.installed => const Color(0xFF3DDC84),
      PackageState.updatable => const Color(0xFFFFB900),
      PackageState.available => const Color(0xFF767676),
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _versionColumn(FluentThemeData theme) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (package.hasUpdate) ...[
            Text(
              '${package.installedVersion ?? '?'} → ${package.availableVersion ?? '?'}',
              style: theme.typography.caption
                  ?.copyWith(color: const Color(0xFFFFB900)),
              textAlign: TextAlign.end,
            ),
          ] else
            Text(
              package.displayVersion ?? '—',
              style: theme.typography.caption,
              textAlign: TextAlign.end,
            ),
          const SizedBox(height: 2),
          Text(
            _stateLabel,
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String get _stateLabel => switch (package.state) {
        PackageState.installed => 'Installed',
        PackageState.updatable => 'Update available',
        PackageState.available => 'Not installed',
      };

  Widget _action(FluentThemeData theme) {
    switch (package.state) {
      case PackageState.available:
        return FilledButton(
          onPressed: onInstall,
          child: const Text('Install'),
        );
      case PackageState.updatable:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(onPressed: onInstall, child: const Text('Update')),
            const SizedBox(width: 6),
            _uninstallButton(),
          ],
        );
      case PackageState.installed:
        return _uninstallButton();
    }
  }

  Widget _uninstallButton() => Tooltip(
        message: 'Uninstall',
        child: IconButton(
          icon: const Icon(FluentIcons.delete, color: Color(0xFFC42B1C)),
          onPressed: onUninstall,
        ),
      );
}
