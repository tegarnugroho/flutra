#include "single_instance.h"

namespace {

// Local\, not Global\: the scope is one logon session, so two users signed in
// to the same machine each get their own instance. That is what "already
// running" means to a user, and Global\ would also need rights a per-user
// install does not have.
//
// The GUID is the installer's AppId. It keeps the name unique without a second
// identifier to keep in step.
constexpr wchar_t kMutexName[] =
    L"Local\\Flutra.SingleInstance."
    L"44359FD9-1412-4751-9983-3F53BB31BA68";

constexpr wchar_t kMessageName[] =
    L"Flutra.ShowExistingInstance."
    L"44359FD9-1412-4751-9983-3F53BB31BA68";

}  // namespace

UINT ShowExistingInstanceMessage() {
  // RegisterWindowMessage returns one value per string for the whole session,
  // so the two processes match without either knowing the other exists, and
  // the value cannot collide with an unrelated window's private messages.
  static const UINT message = ::RegisterWindowMessageW(kMessageName);
  return message;
}

bool ClaimSingleInstance() {
  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kMutexName);
  const DWORD error = ::GetLastError();

  // Fail open. A machine that cannot hand out a mutex should still run the
  // app; a duplicate window is a smaller problem than refusing to start.
  if (mutex == nullptr) {
    return true;
  }

  if (error != ERROR_ALREADY_EXISTS) {
    // Held for the life of the process and released by Windows on exit, so the
    // handle is deliberately not closed.
    return true;
  }

  // Ownership went to the first instance, so this handle is just a reference.
  ::CloseHandle(mutex);

  // The window we are about to wake may be minimised, behind something, or
  // hidden in the tray by "close to tray". It cannot take the foreground by
  // itself while this process holds foreground rights, so give them away
  // first; without this the app would come back invisibly.
  ::AllowSetForegroundWindow(ASFW_ANY);

  const UINT message_id = ShowExistingInstanceMessage();
  if (message_id != 0) {
    // Broadcast rather than hunt for the window: the class name is Flutter's
    // own and shared with every other Flutter app, and the title is whatever
    // the app last set. Windows that never registered this string see an
    // unknown message number and ignore it.
    ::PostMessageW(HWND_BROADCAST, message_id, 0, 0);
  }
  return false;
}

void SurfaceWindow(HWND window) {
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    // Not redundant with SetForegroundWindow: "close to tray" hides the window
    // outright, and a hidden window cannot be brought to the front.
    ::ShowWindow(window, SW_SHOW);
  }
  ::SetForegroundWindow(window);
}
