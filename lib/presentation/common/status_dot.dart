import 'package:fluent_ui/fluent_ui.dart';

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
