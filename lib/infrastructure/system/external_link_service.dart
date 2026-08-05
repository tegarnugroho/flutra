import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../../core/command/command_runner.dart';

/// Opens http(s) links in whatever browser the OS considers default.
///
/// Shells out through the shared [CommandRunner] rather than pulling in
/// `url_launcher`: the package isn't a dependency, this is the only place the
/// app needs it, and every other system interaction here already goes through
/// the runner.
@lazySingleton
class ExternalLinkService {
  ExternalLinkService(this._runner);

  final CommandRunner _runner;

  static final Logger _log = Logger('ExternalLinkService');

  /// Returns false when the link could not be handed off — the caller decides
  /// whether that is worth telling the user about.
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    // Refuse anything that isn't a web link: this runs a shell command, and
    // `start` would happily launch a local executable given the chance.
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _log.warning('refused to open non-web link: $url');
      return false;
    }
    if (!Platform.isWindows) {
      // TODO(platform): the app is Windows-only today; add xdg-open/open here
      // if that ever changes.
      _log.warning('opening links is only implemented for Windows');
      return false;
    }
    try {
      // The empty argument is `start`'s title parameter — without it a quoted
      // URL is taken as the window title and nothing opens.
      final result = await _runner.run(
        'cmd',
        ['/c', 'start', '', uri.toString()],
        timeout: const Duration(seconds: 10),
      );
      return result.isSuccess;
    } catch (e) {
      _log.warning('could not open $url: $e');
      return false;
    }
  }
}
