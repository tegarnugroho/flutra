import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'task_window_routes.dart';

/// Whether a window is kept warm at all.
///
/// Off. The pool works by reusing one engine for whatever window is asked for
/// next, and reusing an engine means resizing and re-theming a window that is
/// already laid out — which is where the second open came out cropped and
/// half-transparent. The two causes found are fixed (see [TaskWindowHost]), but
/// none of it can be exercised in a test: multi-window needs a real desktop
/// session.
///
/// So it ships off. Every open takes the direct path, which is what the app did
/// before and is known to work. Flip this to true to try the warm path, and
/// watch the `WindowOpen` trace to see which route an open took.
const bool kWarmWindowPoolEnabled = false;

/// How long after the main window settles the first warm window is created.
///
/// Not at startup: a second engine booting while the app is still laying out
/// its first screen is exactly the stutter this is meant to remove.
const Duration kWarmUpDelay = Duration(seconds: 3);

/// How long a warm window gets to answer a ping before it is written off.
const Duration kHealthCheckTimeout = Duration(milliseconds: 500);

/// Keeps one hidden window booted and waiting.
///
/// Opening a window costs an engine, an isolate, `main()` and a first frame —
/// several hundred milliseconds that no amount of frame maths can hide. The
/// only way to not pay it on the click is to have paid it already.
///
/// Everything here is best-effort. If the warm window is missing, dead, or slow
/// to answer, [acquire] returns null and the caller creates a window the old
/// way; the worst case is the speed the app had before this existed.
@lazySingleton
class WarmWindowPool {
  static final Logger _log = Logger('WarmWindowPool');

  WindowController? _warm;
  Future<void>? _warmingUp;
  Timer? _scheduled;

  /// True when a window is standing by. Only a hint — [acquire] still checks.
  bool get isReady => _warm != null;

  /// Schedules the first warm-up, once the app has something on screen.
  void scheduleWarmUp({Duration delay = kWarmUpDelay}) {
    if (!kWarmWindowPoolEnabled) return;
    _scheduled?.cancel();
    _scheduled = Timer(delay, () => unawaited(warmUp()));
  }

  /// Creates the standby window, unless one is already up or on its way.
  Future<void> warmUp() {
    if (!kWarmWindowPoolEnabled || _warm != null) return Future.value();
    return _warmingUp ??= _create().whenComplete(() => _warmingUp = null);
  }

  Future<void> _create() async {
    try {
      final stopwatch = Stopwatch()..start();
      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode({'businessId': kStandbyWindow}),
          hiddenAtLaunch: true,
        ),
      );
      _warm = controller;
      _log.fine('warm window ready in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      // A pool that cannot be filled is not an error the user should ever see;
      // every open just takes the slow path.
      _log.warning('could not warm a window: $e');
      _warm = null;
    }
  }

  /// Hands the standby window a job.
  ///
  /// Returns the window that took it, or null when there was nothing to hand it
  /// to or it did not answer — the caller then creates a window itself. Either
  /// way a fresh warm-up is scheduled, so the *next* open is quick.
  ///
  /// The controller comes back because callers track their windows by id: the
  /// About window re-shows the one already open instead of making a second.
  Future<WindowController?> acquire(Map<String, dynamic> args) async {
    if (!kWarmWindowPoolEnabled) return null;
    final controller = _warm;
    if (controller == null) {
      unawaited(warmUp());
      return null;
    }
    // Claimed up front: a second open must not be handed the same window.
    _warm = null;

    try {
      // The window may have been closed, or its engine torn down, without this
      // side hearing about it. A ping that answers proves both.
      final alive = await controller
          .invokeMethod<bool>(kPingMethod)
          .timeout(kHealthCheckTimeout);
      if (alive != true) throw StateError('standby window did not answer');

      await controller.invokeMethod<bool>(kNavigateMethod, jsonEncode(args));
      _scheduleNext();
      return controller;
    } catch (e) {
      _log.warning('warm window unusable, falling back to a new one: $e');
      _scheduleNext();
      return null;
    }
  }

  /// A used window is never recycled: it holds the state of the job it just
  /// did, and a clean engine is worth more than the milliseconds saved.
  void _scheduleNext() => scheduleWarmUp(delay: const Duration(seconds: 1));

  /// Drops the standby window on app quit, so it does not outlive the app.
  @disposeMethod
  void dispose() {
    _scheduled?.cancel();
    final controller = _warm;
    _warm = null;
    if (controller == null) return;
    // Nothing to await on the way out; the OS reclaims it either way.
    unawaited(Future(() async {
      try {
        await controller.invokeMethod<bool>(kCloseMethod);
      } catch (_) {}
    }));
  }
}

/// Times one window open, in debug builds only.
///
/// t0 click → t1 create/handover issued → t2 content ready → t3 visible. The
/// numbers are the only way to tell a warm open from a cold one without
/// guessing at it.
class WindowOpenTrace {
  WindowOpenTrace(this.label) : _clock = Stopwatch()..start();

  static final Logger _log = Logger('WindowOpen');

  final String label;
  final Stopwatch _clock;
  final List<String> _marks = [];

  void mark(String step) {
    if (!kDebugMode) return;
    _marks.add('$step=${_clock.elapsedMilliseconds}ms');
  }

  /// [warm] says which path was taken, which is the point of the whole trace.
  void done({required bool warm}) {
    if (!kDebugMode) return;
    _marks.add('shown=${_clock.elapsedMilliseconds}ms');
    _log.info('$label (${warm ? 'warm' : 'cold'}): ${_marks.join(' ')}');
  }
}
