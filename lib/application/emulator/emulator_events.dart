import 'dart:async';

import 'package:injectable/injectable.dart';

/// App-wide bus signalling that the AVD set changed and lists should reload.
///
/// Used to bridge the separate Create-Emulator OS window (a different isolate)
/// back to the main window: when a sub-window creates an AVD it messages the
/// main window, whose handler fires [emitChanged].
@singleton
class EmulatorEvents {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get onChanged => _controller.stream;

  void emitChanged() {
    if (!_controller.isClosed) _controller.add(null);
  }

  @disposeMethod
  void dispose() => _controller.close();
}
