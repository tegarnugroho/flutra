import 'package:android_sdk_manager/presentation/window/window_placement.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the native side of window_manager so the frame maths can be
/// asserted without a real window.
void _mockWindowManager(Rect? bounds) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        call,
      ) async {
        if (call.method != 'getBounds') return null;
        if (bounds == null) {
          throw PlatformException(code: 'no-window');
        }
        return <dynamic, dynamic>{
          'x': bounds.left,
          'y': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        };
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  test('centres the task window over the opener', () async {
    _mockWindowManager(const Rect.fromLTWH(100, 50, 1280, 800));

    final frame = await centeredOverMainWindow(const Size(720, 640));

    expect(frame, isNotNull);
    // 100 + (1280 - 720) / 2, 50 + (800 - 640) / 2
    expect(frame, [380.0, 130.0, 720.0, 640.0]);
  });

  test('follows the opener onto a second monitor', () async {
    // A main window living at a negative origin, as a left-hand monitor does.
    _mockWindowManager(const Rect.fromLTWH(-1920, 0, 1000, 900));

    final frame = await centeredOverMainWindow(kWizardWindowSize);

    expect(frame![0], -1920 + (1000 - kWizardWindowSize.width) / 2);
    expect(frame[1], (900 - kWizardWindowSize.height) / 2);
  });

  test('keeps the requested size even when the opener is smaller', () async {
    _mockWindowManager(const Rect.fromLTWH(0, 0, 400, 300));

    final frame = await centeredOverMainWindow(kWizardWindowSize);

    expect(frame![2], kWizardWindowSize.width);
    expect(frame[3], kWizardWindowSize.height);
    // Negative origin is fine — the sub-window's fallback is for a *missing*
    // frame, not an off-centre one, and Windows clamps it onto a monitor.
    expect(frame[0], lessThan(0));
  });

  test('returns null when the opener has no readable bounds', () async {
    _mockWindowManager(null);

    expect(await centeredOverMainWindow(kWizardWindowSize), isNull);
  });

  test('the wizard floor fits inside its default size', () {
    expect(kWizardWindowMinSize.width, lessThanOrEqualTo(kWizardWindowSize.width));
    expect(
      kWizardWindowMinSize.height,
      lessThanOrEqualTo(kWizardWindowSize.height),
    );
  });
}
