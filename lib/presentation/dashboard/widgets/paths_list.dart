import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../domain/entities/environment_snapshot.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'grouped_list.dart';

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
          if (hasPath) _CopyButton(value: path!, label: label),
        ],
      ),
    );
  }
}

/// Copies a path to the clipboard and confirms via the app's usual info bar.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.value, required this.label});

  final String value;
  final String label;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _hovered = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    await displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: Text('${widget.label} path copied'),
        content: Text(widget.value),
        severity: InfoBarSeverity.info,
        isLong: true,
        onClose: close,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: 'Copy path',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              FluentIcons.copy,
              size: 13,
              color: _hovered ? palette.textPrimary : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
