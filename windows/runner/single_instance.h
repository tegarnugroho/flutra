#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

// Window message a second launch broadcasts to ask the running instance to
// show itself. Both processes derive it from the same string, so they agree on
// its value without sharing anything else. 0 if it could not be registered.
UINT ShowExistingInstanceMessage();

// True when this process is the first instance.
//
// When it returns false the running instance has already been asked to
// surface, and this process must exit without creating a window.
bool ClaimSingleInstance();

// Brings `window` back from minimised, hidden, or merely behind something.
void SurfaceWindow(HWND window);

#endif  // RUNNER_SINGLE_INSTANCE_H_
