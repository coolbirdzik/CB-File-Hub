#ifndef RUNNER_PRIORITY_MESSAGE_LOOP_H_
#define RUNNER_PRIORITY_MESSAGE_LOOP_H_

#include <windows.h>

// With the Flutter UI on the platform thread, the engine keeps a posted wake-up
// message queued while Dart has tasks to run. GetMessage returns posted
// messages before input and WM_TIMER, so a long run of slow frames (debug
// builds) delays mouse wheel and touchpad (DirectManipulation is driven by
// WM_TIMER) scroll updates. Take those first on each turn.
//
// Only scroll messages jump ahead. Keyboard and click input stays in order:
// a key down must not pass the WM_CHAR posted for the previous key, and a
// click must not pass a pending modifier key down. Wheel messages carry their
// modifiers in wParam.
inline bool TakePriorityMessage(MSG* msg) {
  return ::PeekMessageW(msg, nullptr, WM_MOUSEWHEEL, WM_MOUSEWHEEL,
                        PM_REMOVE) ||
         ::PeekMessageW(msg, nullptr, WM_MOUSEHWHEEL, WM_MOUSEHWHEEL,
                        PM_REMOVE) ||
         ::PeekMessageW(msg, nullptr, WM_TIMER, WM_TIMER, PM_REMOVE);
}

// Runs until WM_QUIT. PeekMessage returns WM_QUIT regardless of its filter.
inline void RunPriorityMessageLoop() {
  MSG msg;
  while (true) {
    if (TakePriorityMessage(&msg)) {
      if (msg.message == WM_QUIT) return;
    } else if (::GetMessageW(&msg, nullptr, 0, 0) <= 0) {
      return;
    }
    // Flutter's keyboard handling expects the WM_CHAR this posts.
    ::TranslateMessage(&msg);
    ::DispatchMessageW(&msg);
  }
}

#endif  // RUNNER_PRIORITY_MESSAGE_LOOP_H_
