import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../../core/command/command_runner.dart';
import '../../core/platform/platform_service.dart';

/// Opens http(s) links in whatever browser the OS considers default.
///
/// Shells out through the shared [CommandRunner] rather than pulling in
/// `url_launcher`: the package isn't a dependency, this is the only place the
/// app needs it, and every other system interaction here already goes through
/// the runner.
@lazySingleton
class ExternalLinkService {
  ExternalLinkService(this._runner, this._platform);

  final CommandRunner _runner;
  final PlatformService _platform;

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
    // Each desktop has its own opener; the empty argument on Windows is
    // `start`'s title parameter — without it a quoted URL is taken as the
    // window title and nothing opens.
    final (command, arguments) = switch (_platform.operatingSystem) {
      'windows' => ('cmd', ['/c', 'start', '', uri.toString()]),
      'macos' => ('open', [uri.toString()]),
      _ => ('xdg-open', [uri.toString()]),
    };

    try {
      final result = await _runner.run(
        command,
        arguments,
        timeout: const Duration(seconds: 10),
      );
      return result.isSuccess;
    } catch (e) {
      _log.warning('could not open $url: $e');
      return false;
    }
  }
}
