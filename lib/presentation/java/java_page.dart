import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/java/java_cubit.dart';
import '../../core/di/injection.dart';
import '../../core/platform/system_actions.dart';
import '../../domain/entities/jdk.dart';
import '../common/confirm_dialog.dart';
import '../common/empty_state.dart';
import '../common/loading_switcher.dart';
import '../common/outlined_action_button.dart';
import '../common/page_scaffold.dart';
import '../common/skeleton/skeleton_layouts.dart';
import '../common/tile_box.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'widgets/java_identity_panel.dart';
import 'widgets/jdk_install_dialog.dart';
import 'widgets/jdk_tile.dart';

/// Java: which JDKs are installed, and which one the toolchain uses.
class JavaPage extends StatelessWidget {
  const JavaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<JavaCubit>()..load(),
      child: const _JavaView(),
    );
  }
}

class _JavaView extends StatelessWidget {
  const _JavaView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<JavaCubit, JavaState>(
      listenWhen: (p, c) =>
          c.errorMessage != null && p.errorMessage != c.errorMessage,
      listener: (context, state) {
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('Error'),
            content: Text(state.errorMessage!),
            severity: InfoBarSeverity.error,
            isLong: true,
            onClose: () {
              close();
              context.read<JavaCubit>().clearError();
            },
          ),
        );
      },
      builder: (context, state) {
        final cubit = context.read<JavaCubit>();
        return PageScaffold(
          title: 'Java',
          titleMeta: state.jdks.isEmpty ? null : state.countLabel,
          actions: [
            OutlinedActionButton(
              icon: FluentIcons.download,
              label: 'Install JDK…',
              onPressed: () => showJdkInstallDialog(context, cubit),
            ),
            OutlinedActionButton(
              icon: FluentIcons.add,
              label: 'Add JDK…',
              onPressed: () => _addManual(context, cubit),
            ),
            OutlinedActionButton(
              icon: FluentIcons.refresh,
              label: 'Refresh',
              busy: state.isLoading,
              onPressed: () => cubit.load(force: true),
            ),
          ],
          child: LoadingSwitcher(
            showSkeleton: state.isFirstLoad,
            skeleton: const JavaSkeleton(),
            builder: (context) => _loaded(context, state, cubit),
          ),
        );
      },
    );
  }

  Widget _loaded(BuildContext context, JavaState state, JavaCubit cubit) {
    if (state.status == JavaStatus.failure && state.jdks.isEmpty) {
      return EmptyState(
        icon: FluentIcons.error_badge,
        isError: true,
        title: 'Could not look for JDKs',
        message: state.errorMessage ?? 'Unknown error.',
        actionLabel: 'Retry',
        onAction: () => cubit.load(force: true),
      );
    }

    final active = state.active;
    final warning = state.compatibilityWarning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              JavaIdentityPanel(
                active: active,
                configuredForFlutter: state.configuredForFlutter,
                busy: active != null && state.isBusy(active.jdk.path),
                onSetForFlutter: active == null || !active.jdk.isSelectable
                    ? null
                    : () => cubit.useForFlutter(active.jdk),
                onInstall: () => showJdkInstallDialog(context, cubit),
              ),
              // Only on a known conflict: a hint that shows when things are
              // fine is a hint nobody reads when they are not.
              if (warning != null) ...[
                const SizedBox(height: 10),
                _CompatibilityHint(message: warning),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(child: _list(context, state, cubit)),
      ],
    );
  }

  Widget _list(BuildContext context, JavaState state, JavaCubit cubit) {
    if (state.jdks.isEmpty) {
      return EmptyState(
        icon: FluentIcons.error_badge,
        title: 'No JDKs found',
        message:
            'Nothing turned up in the registry, the usual install folders, '
            '.jdks, JAVA_HOME or PATH.',
        actionLabel: 'Add JDK…',
        actionIcon: FluentIcons.add,
        onAction: () => _addManual(context, cubit),
      );
    }
    return ListView.separated(
      padding: kPageBodyPadding,
      itemCount: state.jdks.length,
      separatorBuilder: (_, _) => const SizedBox(height: TileBox.gap),
      itemBuilder: (context, i) {
        final jdk = state.jdks[i];
        return JdkTile(
          key: ValueKey(jdk.path),
          jdk: jdk,
          isActiveForFlutter: state.isActiveForFlutter(jdk),
          task: state.taskFor(jdk.path),
          onUseForFlutter: () => cubit.useForFlutter(jdk),
          onSetJavaHome: () => _setJavaHome(context, cubit, jdk, state.javaHome),
          onShowInFolder: () =>
              getIt<SystemActions>().revealInFileManager(jdk.path),
          onCopyPath: () => _copyPath(context, jdk.path),
        );
      },
    );
  }

  Future<void> _copyPath(BuildContext context, String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) return;
    await displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Path copied'),
        content: Text(path),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  /// Writes `JAVA_HOME` after saying exactly what is being replaced.
  static Future<void> _setJavaHome(
    BuildContext context,
    JavaCubit cubit,
    Jdk jdk,
    String? current,
  ) async {
    const caveat =
        'Only affects newly started terminals and apps — this app and any '
        'open shell keep the old value until they restart.';
    final ok = await showConfirmDialog(
      context,
      title: 'Set JAVA_HOME',
      message:
          '${current == null ? 'JAVA_HOME is not set.' : 'Current: $current'}'
          '\nNew: ${jdk.path}\n\n$caveat',
      confirmLabel: 'Set JAVA_HOME',
      destructive: false,
    );
    if (!ok) return;

    final note = await cubit.setJavaHome(jdk);
    if (note == null || !context.mounted) return;
    await displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('JAVA_HOME updated'),
        content: const Text(caveat),
        severity: InfoBarSeverity.success,
        isLong: true,
        onClose: close,
      ),
    );
  }

  Future<void> _addManual(BuildContext context, JavaCubit cubit) async {
    final picked = await getDirectoryPath(confirmButtonText: 'Select JDK');
    if (picked == null || !context.mounted) return;
    final error = await cubit.addManualJdk(picked);
    if (error == null || !context.mounted) return;
    await displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Not added'),
        content: Text(error),
        severity: InfoBarSeverity.error,
        isLong: true,
        onClose: close,
      ),
    );
  }
}

/// The one-line warning under the panel when the active JDK and the Gradle
/// Flutter ships cannot work together.
class _CompatibilityHint extends StatelessWidget {
  const _CompatibilityHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(FluentIcons.warning, size: 13, color: palette.statusWarn),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.of(
              context,
            ).caption.copyWith(color: palette.statusWarn),
          ),
        ),
      ],
    );
  }
}
