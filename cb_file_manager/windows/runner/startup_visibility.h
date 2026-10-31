#ifndef RUNNER_STARTUP_VISIBILITY_H_
#define RUNNER_STARTUP_VISIBILITY_H_

#include <windows.h>

// ShowWindow(SW_MAXIMIZE), including window_manager's SC_MAXIMIZE, normally
// exposes a hidden HWND. Keep its final layout while Flutter renders offscreen.
inline void HoldStartupVisibility(bool held, WINDOWPOS* position) {
  if (held && position) position->flags &= ~SWP_SHOWWINDOW;
}

#endif  // RUNNER_STARTUP_VISIBILITY_H_
