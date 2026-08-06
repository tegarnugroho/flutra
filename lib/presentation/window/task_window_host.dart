import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
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

  /// Bumped on every navigation so the fade replays for the new content.
  int _generation = 0;

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

    // Size and position are applied while the window is still hidden, so the
    // first frame of the new content is already in its final place.
    await applyWindowChrome(route, args);
    if (!mounted) return;
    setState(() {
      _route = route;
      _args = args;
      _generation++;
    });
    _revealAfterFrame();
  }

  /// Shows the window once the frame after this one has rendered.
  ///
  /// Ordering, not a timer: the callback fires when the content is actually on
  /// the surface, so there is no blank window and no guessed delay.
  void _revealAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.show();
      } on MissingPluginException {
        await widget.controller.show();
      } catch (_) {}
    });
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
      builder: (context, child) => _FadeIn(
        key: ValueKey(_generation),
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

/// Fades its child in once, on mount.
class _FadeIn extends StatefulWidget {
  const _FadeIn({super.key, required this.child});

  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kWindowFadeIn,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        child: widget.child,
      );
}
