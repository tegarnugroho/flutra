import 'package:fluent_ui/fluent_ui.dart';

/// The Flutter logo, drawn rather than bundled.
///
/// The mark is two flat polygons, so a painter is smaller than an asset and
/// takes its colour from the palette like everything else on the page.
class FlutterGlyph extends StatelessWidget {
  const FlutterGlyph({super.key, required this.color, this.size = 16});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FlutterGlyphPainter(color)),
    );
  }
}

class _FlutterGlyphPainter extends CustomPainter {
  const _FlutterGlyphPainter(this.color);

  final Color color;

  /// The logo is authored on a 24×24 grid; every point below is in that space.
  static const _grid = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _grid;
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    // Upper blade: the diagonal running from the top-right down to the fold.
    final upper = Path()
      ..moveTo(14.314, 0)
      ..lineTo(2.3, 12)
      ..lineTo(6, 15.7)
      ..lineTo(21.684, 0.013)
      ..lineTo(14.327, 0.013)
      ..close();

    // Lower blade: the second fold, mirrored about the middle.
    final lower = Path()
      ..moveTo(14.328, 11.072)
      ..lineTo(7.857, 17.53)
      ..lineTo(14.327, 24)
      ..lineTo(21.7, 24)
      ..lineTo(15.24, 17.532)
      ..lineTo(21.7, 11.072)
      ..close();

    canvas.drawPath(upper, paint);
    canvas.drawPath(lower, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlutterGlyphPainter old) => old.color != color;
}
