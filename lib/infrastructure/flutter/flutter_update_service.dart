import 'package:injectable/injectable.dart';

import '../../domain/entities/flutter_update_status.dart';
import '../../domain/repositories/flutter_repository.dart';
import 'flutter_releases_service.dart';

/// Answers "is the installed Flutter SDK out of date?" for every screen that
/// asks (dashboard, Updates, the Flutter SDK page).
@lazySingleton
class FlutterUpdateService {
  FlutterUpdateService(this._releases, this._repository);

  final FlutterReleasesService _releases;
  final FlutterRepository _repository;

  /// Compares the checkout's HEAD with `current_release[channel]`.
  ///
  /// Returns null when the release index is unavailable (offline, no cache) —
  /// callers should treat that as "unknown", not as "up to date".
  Future<FlutterUpdateStatus?> check({
    required String channel,
    bool forceRefresh = false,
  }) async {
    try {
      final index = await _releases.getReleases(forceRefresh: forceRefresh);
      final head = await _repository.sdkHeadHash();
      return FlutterUpdateStatus(
        channel: channel,
        headHash: head,
        installed: head == null ? null : index.byHash(head),
        latest: index.latestFor(channel),
      );
    } catch (_) {
      return null;
    }
  }
}
