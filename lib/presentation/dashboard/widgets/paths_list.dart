import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/environment_snapshot.dart';
import '../../common/copy_icon_button.dart';
import '../../common/grouped_list.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Resolved filesystem locations. Versions live in the toolchain list, so this
/// group only carries paths.
class PathsList extends StatelessWidget {
  const PathsList({super.key, required this.snapshot});

  final EnvironmentSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      ('Android SDK', snapshot.sdkPath),
      ('Java', snapshot.javaPath),
      ('Flutter', snapshot.flutterPath),
    ];
    return GroupedList(
      children: [
        for (final row in rows) PathRow(label: row.$1, path: row.$2),
      ],
    );
  }
}

/// Label column + ellipsized mono path + copy action.
class PathRow extends StatelessWidget {
  const PathRow({super.key, required this.label, required this.path});

  static const _labelWidth = 110.0;

  final String label;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasPath = path != null && path!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(label, style: AppTextStyles.rowLabel),
          ),
          Expanded(
            child: Text(
              hasPath ? path! : '—',
              style: hasPath
                  ? AppTextStyles.monoPath
                  : AppTextStyles.monoPath.copyWith(color: palette.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (hasPath) CopyIconButton(value: path!, label: '$label path'),
        ],
      ),
    );
  }
}
