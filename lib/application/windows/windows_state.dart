part of 'windows_cubit.dart';

enum WindowsStatus { initial, loading, ready, failure }

/// Immutable state for the Windows toolchain screen.
class WindowsState extends Equatable {
  const WindowsState({
    this.status = WindowsStatus.initial,
    this.toolchain = const WindowsToolchain(),
    this.setup,
    this.pending,
    this.errorMessage,
  });

  final WindowsStatus status;
  final WindowsToolchain toolchain;

  /// The installer run in flight, or the last one's result.
  final WindowsSetupEvent? setup;

  /// A short in-app action running on one requirement — the only one is
  /// `flutter config`, which needs no installer.
  final WindowsRequirementKind? pending;

  final String? errorMessage;

  bool get isLoading => status == WindowsStatus.loading;

  /// True until the first scan settles, so the screen shows its skeleton from
  /// the very first frame.
  bool get isFirstLoad =>
      toolchain.installs.isEmpty &&
      toolchain.sdks.isEmpty &&
      (status == WindowsStatus.initial || status == WindowsStatus.loading);

  /// True while any operation is running. Every action disables: the VS
  /// Installer is machine-wide, and two at once is an error message about the
  /// first one.
  bool get isBusy {
    if (pending != null) return true;
    final event = setup;
    return event != null && !event.stage.isTerminal;
  }

  WindowsState copyWith({
    WindowsStatus? status,
    WindowsToolchain? toolchain,
    WindowsSetupEvent? setup,
    bool clearSetup = false,
    WindowsRequirementKind? pending,
    bool clearPending = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WindowsState(
      status: status ?? this.status,
      toolchain: toolchain ?? this.toolchain,
      setup: clearSetup ? null : (setup ?? this.setup),
      pending: clearPending ? null : (pending ?? this.pending),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, toolchain, setup, pending, errorMessage];
}
