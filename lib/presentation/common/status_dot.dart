import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_text_styles.dart';

/// A small filled circle — the app's only status signal.
///
/// Pass a null [color] for an invisible placeholder that still reserves the
/// slot, so values in a list stay aligned whether or not a row has a status.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, this.color, this.size = 6});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: color == null
          ? null
          : DecoratedBox(
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
    );
  }
}

/// Dot plus one line of text — the app's standard "how are things" summary,
/// used instead of banners.
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.color,
    required this.message,
    this.trailing,
  });

  final Color color;
  final String message;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StatusDot(color: color, size: 7),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.statusLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}
