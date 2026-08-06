import 'dart:async';

import 'package:injectable/injectable.dart';

/// The shell's navigable destinations, in the order the pane lists them.
///
/// Named rather than indexed: the pane's index space shifts whenever a section
/// label or a footer item moves, and a caller three files away should not have
/// to know that.
enum ShellDestination {
  dashboard,
  sdkManager,
  virtualDevices,
  licenses,
  java,
  logcat,
  updates,
  flutterSdk,
  flutterDoctor,
  windows,
  devices,
  settings,
}

/// One request to move the shell somewhere.
class ShellNavigationRequest {
  const ShellNavigationRequest(this.destination, {this.autoRun = false});

  final ShellDestination destination;

  /// Asks the destination to start its main action on arrival — used by the
  /// Dashboard's "Run flutter doctor" shortcut.
  final bool autoRun;
}

/// App-wide bus for "take me to that screen".
///
/// The pane's selected index lives in `AppShell`'s State, which nothing else
/// can reach. This is the same shape as [EmulatorEvents]: a singleton stream
/// the shell listens to, so any page can ask to navigate without the shell
/// having to hand a callback down through every widget.
@singleton
class ShellNavigator {
  final StreamController<ShellNavigationRequest> _controller =
      StreamController<ShellNavigationRequest>.broadcast();

  Stream<ShellNavigationRequest> get onNavigate => _controller.stream;

  /// Destinations asked to start their work on arrival, still unclaimed.
  ///
  /// Parked here rather than passed through the shell because the destination
  /// is built *after* the navigation event fires — a listener inside the page
  /// would always be too late to hear it.
  final Set<ShellDestination> _pendingAutoRun = {};

  void go(ShellDestination destination, {bool autoRun = false}) {
    if (_controller.isClosed) return;
    if (autoRun) _pendingAutoRun.add(destination);
    _controller.add(ShellNavigationRequest(destination, autoRun: autoRun));
  }

  /// True once per request: the destination calls this as it builds and the
  /// flag is cleared, so a later rebuild doesn't run the action again.
  bool consumeAutoRun(ShellDestination destination) =>
      _pendingAutoRun.remove(destination);

  @disposeMethod
  void dispose() => _controller.close();
}
