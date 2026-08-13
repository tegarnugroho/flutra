#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "single_instance.h"
#include "utils.h"  // TEMP CLOSE INSTRUMENTATION

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  // TEMP CLOSE INSTRUMENTATION - the controller is reset explicitly so the
  // engine teardown can be timed; normally it dies with the member.
  CloseTrace("~FlutterWindow_begin");
  // A/B: controller left to implicit member destruction.
  CloseTrace("~FlutterWindow_body_end");
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  CloseTrace("engine_teardown_begin");  // TEMP CLOSE INSTRUMENTATION
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  CloseTrace("engine_teardown_end");  // TEMP CLOSE INSTRUMENTATION

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // A second launch broadcasts this instead of starting its own window. Handled
  // before Flutter sees it: the message is ours, and the answer is a native
  // one — the Dart side may not even be running when the window is hidden.
  const UINT show_message = ShowExistingInstanceMessage();
  if (show_message != 0 && message == show_message) {
    SurfaceWindow(hwnd);
    return 0;
  }

  // TEMP CLOSE INSTRUMENTATION - remove before finishing.
  if (message == WM_CLOSE) {
    CloseTrace("WM_CLOSE_received");
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      // TEMP CLOSE INSTRUMENTATION - remove before finishing.
      if (message == WM_CLOSE) {
        CloseTrace("WM_CLOSE_handled_by_plugin");
      }
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
