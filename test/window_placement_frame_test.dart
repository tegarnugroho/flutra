import 'package:android_sdk_manager/presentation/window/window_placement.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('centeredFrame', () {
    // A 1920x1080 screen with a 40px taskbar along the bottom.
    const workArea = Rect.fromLTWH(0, 0, 1920, 1040);
    const size = Size(400, 500);

    test('centres on the opener when there is room', () {
      final frame = centeredFrame(
        parent: const Rect.fromLTWH(500, 200, 1000, 700),
        size: size,
        workArea: workArea,
      );

      expect(frame.center.dx, 1000);
      expect(frame.center.dy, 550);
      expect(frame.size, size);
    });

    test('pulls a child back inside when the opener hugs the right edge', () {
      // Centred, this would start at 1820 and end 300px past the screen.
      final frame = centeredFrame(
        parent: const Rect.fromLTWH(1620, 100, 400, 400),
        size: size,
        workArea: workArea,
      );

      expect(frame.right, workArea.right);
      expect(frame.left, workArea.right - size.width);
    });

    test('keeps a child off the taskbar', () {
      final frame = centeredFrame(
        parent: const Rect.fromLTWH(0, 900, 1920, 140),
        size: size,
        workArea: workArea,
      );

      expect(frame.bottom, lessThanOrEqualTo(workArea.bottom));
    });

    test('never lands above or left of the work area', () {
      final frame = centeredFrame(
        parent: const Rect.fromLTWH(-200, -300, 400, 400),
        size: size,
        workArea: workArea,
      );

      expect(frame.left, workArea.left);
      expect(frame.top, workArea.top);
    });

    test('follows the opener onto a second monitor', () {
      // A display to the right of the primary one, at a negative-y offset.
      const secondary = Rect.fromLTWH(1920, -200, 1280, 1024);
      final frame = centeredFrame(
        parent: const Rect.fromLTWH(2100, 0, 800, 600),
        size: size,
        workArea: secondary,
      );

      expect(frame.center.dx, 2500);
      expect(secondary.contains(frame.topLeft), isTrue);
      expect(frame.right, lessThanOrEqualTo(secondary.right));
    });

    test('a window taller than the screen is pinned, not shrunk', () {
      // The caller picked the size; silently resizing it would be worse than
      // overflowing a short screen.
      const tall = Size(400, 1200);
      final frame = centeredFrame(
        parent: const Rect.fromLTWH(0, 0, 1920, 1040),
        size: tall,
        workArea: workArea,
      );

      expect(frame.size, tall);
      expect(frame.top, workArea.top);
    });

    test('without a work area it simply centres', () {
      final frame = centeredFrame(
        parent: const Rect.fromLTWH(1620, 100, 400, 400),
        size: size,
      );

      expect(frame.center.dx, 1820);
    });
  });
}
