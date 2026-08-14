import 'package:flutra/presentation/window/window_close_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('which windows closing the app takes with it', () {
    // Every window in this app is a window of one process. Closing the main one
    // has to take the sub-windows down first — destroying it while a sub-window's
    // engine was still running crashed the process on Linux rather than ending
    // it. This is the rule that decides which is which, and getting it backwards
    // would have the main window ask itself to close.
    test('a window opened by this app is a child', () {
      expect(isChildWindow('{"businessId":"devLogs","dark":true}'), isTrue);
      expect(isChildWindow('{"businessId":"about"}'), isTrue);
      expect(isChildWindow('{"businessId":"createEmulator"}'), isTrue);
      expect(isChildWindow('{"businessId":"emulatorConsole"}'), isTrue);
    });

    test('the main window is not', () {
      // The runner creates it and the plugin adopts it with no arguments —
      // see MultiWindowManager::AttachMainWindow.
      expect(isChildWindow(''), isFalse);
    });

    test('whitespace is not arguments', () {
      expect(isChildWindow('   '), isFalse);
      expect(isChildWindow('\n'), isFalse);
    });
  });

  group('the close request', () {
    test('is namespaced, so it cannot collide with the plugin\'s own methods',
        () {
      // The plugin routes anything starting with "window_" itself; this rides
      // the per-window channel alongside it.
      expect(kCloseWindowMethod, 'flutra.closeWindow');
      expect(kCloseWindowMethod.startsWith('window_'), isFalse);
    });
  });
}
