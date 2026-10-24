#ifndef RUNNER_FLUTTER_MOUSE_INPUT_GUARD_H_
#define RUNNER_FLUTTER_MOUSE_INPUT_GUARD_H_

#include <windows.h>
#include <commctrl.h>

// Keeps a press in the Flutter view where it began. Cloaking a tab window or
// activating its merge target can transfer capture while a button is held.
class FlutterMouseInputGuard {
 public:
  explicit FlutterMouseInputGuard(HWND view);
  ~FlutterMouseInputGuard();
  FlutterMouseInputGuard(const FlutterMouseInputGuard&) = delete;
  FlutterMouseInputGuard& operator=(const FlutterMouseInputGuard&) = delete;

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR subclass_id,
                                    DWORD_PTR reference);
  HWND view_;
  WPARAM pressed_buttons_ = 0;
};

#endif  // RUNNER_FLUTTER_MOUSE_INPUT_GUARD_H_
