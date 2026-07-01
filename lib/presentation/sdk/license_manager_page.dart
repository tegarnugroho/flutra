import 'package:fluent_ui/fluent_ui.dart';

import '../../core/di/injection.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../common/command_progress_dialog.dart';

/// License Manager: runs `sdkmanager --licenses` and auto-accepts every prompt.
class LicenseManagerPage extends StatelessWidget {
  const LicenseManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ScaffoldPage(
      header: const PageHeader(title: Text('License Manager')),
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(FluentIcons.permissions,
                    size: 34, color: theme.accentColor),
              ),
              const SizedBox(height: 20),
              Text('Accept SDK licenses',
                  textAlign: TextAlign.center,
                  style: theme.typography.subtitle),
              const SizedBox(height: 8),
              Text(
                'Before you can install most SDK packages, Google requires you '
                'to accept their licenses. This runs "sdkmanager --licenses" and '
                'answers yes to every prompt for you.',
                textAlign: TextAlign.center,
                style: theme.typography.body?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                ),
              ),
              const SizedBox(height: 24),
              const InfoBar(
                title: Text('One-time step'),
                content: Text(
                    'You only need to do this once per SDK, or after installing '
                    'new package types.'),
                severity: InfoBarSeverity.info,
                isLong: true,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _acceptAll(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FluentIcons.completed_solid, size: 14),
                      SizedBox(width: 8),
                      Text('Accept all licenses'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptAll(BuildContext context) async {
    final ok = await showCommandProgressDialog(
      context,
      title: 'Accepting licenses',
      start: () => getIt<SdkRepository>().acceptAllLicenses(),
    );
    if (ok && context.mounted) {
      await displayInfoBar(context, builder: (context, close) {
        return InfoBar(
          title: const Text('Licenses accepted'),
          content: const Text('All SDK licenses were accepted.'),
          severity: InfoBarSeverity.success,
          onClose: close,
        );
      });
    }
  }
}
