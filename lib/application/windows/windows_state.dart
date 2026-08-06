part of 'windows_cubit.dart';

enum WindowsStatus { initial, loading, ready, failure }

/// Immutable state for the Windows screen.
class WindowsState extends Equatable {
  const WindowsState({
    this.status = WindowsStatus.initial,
    this.toolchain = const WindowsToolchain(),
    this.setup,
    this.errorMessage,
  });

  final WindowsStatus status;
  final WindowsToolchain toolchain;

  /// The setup run in flight, or the last one's result.
  final WindowsSetupEvent? setup;

  final String? errorMessage;

  bool get isLoading => status == WindowsStatus.loading;

  /// True until the first scan settles, so the screen shows its skeleton from
  /// the very first frame.
  bool get isFirstLoad =>
      toolchain.installs.isEmpty &&
      toolchain.sdks.isEmpty &&
      (status == WindowsStatus.initial || status == WindowsStatus.loading);

  /// True while an installer is running — every action is blocked, because
  /// only one Microsoft installer can run at a time.
  bool get isBusy {
    final event = setup;
    if (event == null) return false;
    return event.stage != WindowsSetupStage.done &&
        event.stage != WindowsSetupStage.failed;
  }

  WindowsState copyWith({
    WindowsStatus? status,
    WindowsToolchain? toolchain,
    WindowsSetupEvent? setup,
    bool clearSetup = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WindowsState(
      status: status ?? this.status,
      toolchain: toolchain ?? this.toolchain,
      setup: clearSetup ? null : (setup ?? this.setup),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, toolchain, setup, errorMessage];
}
