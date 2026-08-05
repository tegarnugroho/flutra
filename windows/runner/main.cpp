#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"
#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One window per session. Launching the exe again — from the Start menu, a
  // desktop shortcut, or the installer's "run now" — surfaces the instance
  // that is already there instead of starting a second copy that would fight
  // it over the same SDK directory and settings file.
  //
  // Checked before anything else is set up: nothing below is worth doing in a
  // process that is about to exit, and the sooner it exits the less the second
  // launch looks like a stall.
  if (!ClaimSingleInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // desktop_multi_window spins up a fresh engine per sub-window and registers
  // only its own channels there, so plugins like window_manager answer with
  // "No implementation found" in those engines. This hook is the plugin's
  // supported way to give every sub-window the same plugin set as the main
  // one — without it the Create Emulator window cannot drop its native
  // caption or size itself.
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    RegisterPlugins(view_controller->engine());
  });

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Flutter SDK Manager", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
