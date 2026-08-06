import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../core/platform/system_actions.dart';
import '../../domain/entities/reclaimable_item.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../trash/trash_service.dart';

/// One update from a removal run.
sealed class ReclaimEvent {
  const ReclaimEvent();
}

/// A line of sdkmanager output, or a note from the executor.
class ReclaimLogged extends ReclaimEvent {
  const ReclaimLogged(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

/// Work on [itemId] began.
class ReclaimItemStarted extends ReclaimEvent {
  const ReclaimItemStarted(this.itemId);

  final String itemId;
}

/// Work on [itemId] ended. [freedBytes] is what the folder measured before it
/// went, so a partial run can still say what it recovered.
class ReclaimItemFinished extends ReclaimEvent {
  const ReclaimItemFinished({
    required this.itemId,
    required this.status,
    required this.freedBytes,
    this.message,
  });

  final String itemId;
  final ReclaimItemStatus status;
  final int freedBytes;
  final String? message;
}

/// Removes superseded SDK packages.
///
/// The platform specifics — ending a process tree, moving a folder to the
/// trash — go through the platform layer, so this reads the same on every OS.
@lazySingleton
class ReclaimExecutor {
  ReclaimExecutor(this._sdk, this._trash, this._actions);

  final SdkRepository _sdk;
  final TrashService _trash;
  final SystemActions _actions;

  /// sdkmanager can spend minutes deleting a large system image.
  static const Duration perItemTimeout = Duration(minutes: 5);

  /// Removes [items] one at a time.
  ///
  /// Never in parallel: sdkmanager locks its repository, and a second one
  /// simply fails. A failure does not stop the rest — each item reports its own
  /// verdict and the run carries on.
  Stream<ReclaimEvent> remove(List<ReclaimableItem> items) async* {
    for (final item in items) {
      yield ReclaimItemStarted(item.id);

      if (item.isBlocked) {
        // Belt and braces: the UI cannot select these, and neither can this.
        yield ReclaimItemFinished(
          itemId: item.id,
          status: ReclaimItemStatus.skipped,
          freedBytes: 0,
          message: item.blockedReason,
        );
        continue;
      }

      yield* _removeOne(item);
    }
  }

  Stream<ReclaimEvent> _removeOne(ReclaimableItem item) async* {
    final folder = Directory(item.folderPath);
    final sizeBefore = item.sizeBytes ?? 0;
    var sdkManagerWorked = false;

    yield ReclaimLogged('Removing ${item.id}…');

    try {
      final command = await _sdk.uninstall(item.id);
      final timer = Timer(
        perItemTimeout,
        () => unawaited(_actions.killProcessTree(command.pid)),
      );
      await for (final line in command.output) {
        yield ReclaimLogged(line.text, isError: line.isError);
      }
      final result = await command.result;
      timer.cancel();
      sdkManagerWorked = result.isSuccess;
      if (!sdkManagerWorked) {
        yield ReclaimLogged(
          'sdkmanager exited with ${result.exitCode}.',
          isError: true,
        );
      }
    } catch (e) {
      // Missing sdkmanager, or the shared lock refusing — both leave the
      // folder to be dealt with below.
      yield ReclaimLogged('$e', isError: true);
    }

    // sdkmanager reports success and leaves the directory behind often enough
    // that the folder, not the exit code, is the thing worth believing.
    if (!folder.existsSync()) {
      yield ReclaimItemFinished(
        itemId: item.id,
        status: ReclaimItemStatus.done,
        freedBytes: sizeBefore,
      );
      return;
    }

    yield ReclaimLogged(
      sdkManagerWorked
          ? 'sdkmanager reported success but the folder is still there — '
              'removing it directly.'
          : 'Removing the folder directly instead.',
      isError: !sdkManagerWorked,
    );

    try {
      // Trashed rather than erased, like every other delete in this app: an
      // instant move on the same volume, and recoverable for 24 hours if this
      // turns out to have been the wrong call.
      await _trash.trash(item.folderPath, label: item.displayName);
      yield ReclaimLogged(
        sdkManagerWorked
            ? 'Removed the leftover directory.'
            : 'Removed via the filesystem — the SDK metadata may be stale '
                'until sdkmanager next runs.',
      );
      yield ReclaimItemFinished(
        itemId: item.id,
        status: ReclaimItemStatus.done,
        freedBytes: sizeBefore,
      );
    } catch (e) {
      yield ReclaimLogged('$e', isError: true);
      yield ReclaimItemFinished(
        itemId: item.id,
        status: ReclaimItemStatus.failed,
        freedBytes: 0,
        message: 'Could not remove ${item.displayName}. Close any running '
            'emulator or Gradle daemon using it, then retry.',
      );
    }
  }
}
