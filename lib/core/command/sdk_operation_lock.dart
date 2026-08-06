import 'package:injectable/injectable.dart';

/// Serialises the operations that write to the Android SDK.
///
/// sdkmanager takes a lock on its own repository, so two installs — or an
/// install and an uninstall — fail in confusing ways when they overlap. Held
/// in one place so the SDK Manager screen, the doctor fixes and the reclaim
/// flow all queue behind the same flag instead of each inventing one.
///
/// Claimed by [SdkRepositoryImpl], which is the only thing that spawns
/// sdkmanager; callers read [isBusy] to disable their own entry points.
@lazySingleton
class SdkOperationLock {
  String? _operation;

  /// What holds the lock, e.g. "An install". Null when free.
  String? get busyLabel => _operation;

  bool get isBusy => _operation != null;

  /// Takes the lock, or returns false when someone else has it.
  bool claim(String operation) {
    if (_operation != null) return false;
    _operation = operation;
    return true;
  }

  void release() => _operation = null;
}
