import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import 'about_window.dart';
import 'create_emulator_window.dart';
import 'dev_logs_window.dart';
import 'emulator_console_window.dart';
import 'task_window_routes.dart';

/// How long the content fades in over once the window is shown. Short enough
/// to be over before the eye settles, long enough to hide a first frame that
/// lands mid-blit.
const Duration kWindowFadeIn = Duration(milliseconds: 120);

/// The one root every task window runs.
///
/// A sub-window used to be a fixed widget chosen in `main()` from its launch
/// arguments. It is a host instead so a window created *ahead of time* — see
/// [WarmWindowPool] — can be told what to become over IPC, which takes the
/// engine start off the path between the click and the window.
///
/// Launch arguments still work and are the fallback: [initialRoute] is applied
/// exactly as before when a window is created for a specific job.
class TaskWindowHost extends StatefulWidget {
  const TaskWindowHost({
    super.key,
    required this.controller,
    required this.initialRoute,
    required this.initialArgs,
  });

  final WindowController controller;

  /// The business id this window boots as, or [kStandbyWindow] when it is a
  /// warm one waiting for a job.
  final String initialRoute;

  final Map<String, dynamic> initialArgs;

  @override
  State<TaskWindowHost> createState() => _TaskWindowHostState();
}

class _TaskWindowHostState extends State<TaskWindowHost> {
  static final Logger _log = Logger('TaskWindowHost');

  late String _route = widget.initialRoute;
  late Map<String, dynamic> _args = widget.initialArgs;

  /// False until the window is actually on screen.
  ///
  /// The content is laid out either way — only its opacity waits. Fading a
  /// window nobody can see yet is how the second open came out half
  /// transparent: the fade ran while it was hidden and was already spent, or
  /// half spent, by the time it appeared.
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.setWindowMethodHandler(_handleCall);
    // A window created for a job shows itself once it has something on screen.
    // A standby one stays hidden until it is given one.
    if (_route != kStandbyWindow) _revealAfterFrame();
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case kPingMethod:
        // Answering at all is the whole answer: it proves this engine is alive
        // and its channel is registered.
        return true;
      case kNavigateMethod:
        await _navigate(call.arguments as String? ?? '');
        return true;
      case kCloseMethod:
        // Only ever sent to a standby window on app quit.
        try {
          await windowManager.close();
        } catch (_) {}
        return true;
      default:
        return null;
    }
  }

  /// Becomes [rawArgs]' window: chrome first, then content, then show.
  Future<void> _navigate(String rawArgs) async {
    Map<String, dynamic> args;
    try {
      args = jsonDecode(rawArgs) as Map<String, dynamic>;
    } catch (e) {
      _log.warning('ignored a malformed navigate payload: $e');
      return;
    }
    final route = args['businessId'] as String?;
    if (route == null || route == kStandbyWindow) return;

    // Content first, hidden and transparent, so the resize below has something
    // of the right shape to lay out against.
    if (!mounted) return;
    setState(() {
      _route = route;
      _args = args;
      _revealed = false;
    });

    // Size and position are applied while the window is still hidden, so the
    // first visible frame is already in its final place.
    await applyWindowChrome(route, args);
    if (!mounted) return;

    // A warm window is already laid out at whatever size it booted with, so
    // this resize happens *live* — and it takes a frame or two to reach the
    // surface. Showing before it lands puts the old, differently-sized surface
    // on screen: the second open rendered cropped and half-transparent.
    //
    // A window created for the job never hits this, because it is sized before
    // its first frame exists.
    await _settleLayout();
    if (!mounted) return;
    await _reveal();
  }

  /// Waits for the view size to stop changing, so a resize is fully through
  /// layout and paint before anything is shown.
  ///
  /// Waits on frames, not on a clock: it ends as soon as two consecutive frames
  /// agree. The cap is a ceiling for the case where they never do, not a delay
  /// anyone pays in the normal path.
  Future<void> _settleLayout() async {
    const maxFrames = 12;
    Size? previous;
    var stable = 0;
    for (var frame = 0; frame < maxFrames; frame++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      final size = View.maybeOf(context)?.physicalSize;
      if (size == previous) {
        if (++stable >= 2) return;
      } else {
        stable = 0;
        previous = size;
      }
    }
  }

  /// Shows the window once its content has rendered, then fades that content
  /// in — in that order, so the fade is never spent on a hidden window.
  Future<void> _reveal() async {
    await SchedulerBinding.instance.endOfFrame;
    try {
      await windowManager.show();
    } on MissingPluginException {
      await widget.controller.show();
    } catch (_) {}
    if (mounted) setState(() => _revealed = true);
  }

  void _revealAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  Widget build(BuildContext context) {
    final dark = _args['dark'] == true;
    return FluentApp(
      title: 'Flutter SDK Manager',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Opacity only, and only once the window is up. Laid out throughout, so
      // the first visible frame is the finished one.
      builder: (context, child) => AnimatedOpacity(
        opacity: _revealed ? 1 : 0,
        duration: kWindowFadeIn,
        curve: Curves.easeOut,
        child: child ?? const SizedBox.shrink(),
      ),
      home: _content(dark),
    );
  }

  Widget _content(bool dark) {
    switch (_route) {
      case kCreateEmulatorWindow:
        return CreateEmulatorWindowApp.body(
          windowController: widget.controller,
        );
      case kEmulatorConsoleWindow:
        return EmulatorConsoleWindowApp.body(
          windowController: widget.controller,
          avdName: _args['avd'] as String? ?? '',
        );
      case kDevLogsWindow:
        return DevLogsWindowApp.body(windowController: widget.controller);
      case kAboutWindow:
        return AboutWindowApp.body(windowController: widget.controller);
      default:
        // Standby: the app's own background and nothing else, so a window that
        // somehow becomes visible early shows a themed surface rather than the
        // white the OS would paint.
        return const ScaffoldPage(content: SizedBox.expand());
    }
  }
}
