import 'package:fluent_ui/fluent_ui.dart';

import '../../core/di/injection.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../common/command_progress_dialog.dart';
import '../common/grouped_list.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../theme/app_text_styles.dart';

/// License Manager: runs `sdkmanager --licenses` and auto-accepts every prompt.
///
/// Note: sdkmanager only exposes licences as an interactive prompt stream, so
/// there is no per-licence list to render — this page is the one-shot action.
class LicenseManagerPage extends StatelessWidget {
  const LicenseManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Licenses',
      actions: [
        OutlinedActionButton(
          icon: FluentIcons.completed_solid,
          label: 'Accept all',
          onPressed: () => _acceptAll(context),
        ),
      ],
      child: SingleChildScrollView(
        padding: kPageBodyPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('SDK licenses'),
            const SizedBox(height: 8),
            GroupedBox(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Accept SDK licenses',
                      style: AppTextStyles.heroTitle),
                  const SizedBox(height: 8),
                  const Text(
                    'Before you can install most SDK packages, Google requires '
                    'you to accept their licenses. "Accept all" runs '
                    '"sdkmanager --licenses" and answers yes to every prompt.',
                    style: AppTextStyles.statusLine,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'One-time step — you only need this once per SDK, or after '
                    'installing new package types.',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 16),
                  OutlinedActionButton(
                    icon: FluentIcons.completed_solid,
                    label: 'Accept all licenses',
                    onPressed: () => _acceptAll(context),
                  ),
                ],
              ),
            ),
          ],
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
