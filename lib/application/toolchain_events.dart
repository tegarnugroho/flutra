import 'dart:async';

import 'package:injectable/injectable.dart';

/// App-wide bus signalling that the toolchain changed and anything showing its
/// status should re-read it.
///
/// The Dashboard and the Java page look at the same toolchain from two screens.
/// Installing a JDK on one has to change the other, and the Dashboard's cubit is
/// built per visit — so without this, a status that changed while the Dashboard
/// was on screen stayed wrong until the app restarted.
///
/// Fired from [JavaToolchainService.invalidate], not from the cubits: the same
/// call that drops the cached scan is the one that announces it, so a new caller
/// cannot invalidate and forget to tell anyone.
@singleton
class ToolchainEvents {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get onChanged => _controller.stream;

  void emitChanged() {
    if (!_controller.isClosed) _controller.add(null);
  }

  @disposeMethod
  void dispose() => _controller.close();
}
