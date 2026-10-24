// Standalone Win32 regression test: no Flutter engine or application E2E.
#include "../flutter_mouse_input_guard.h"

#include <iostream>
#include <stdexcept>

namespace {
struct Input {
  int downs = 0, ups = 0, moves = 0, cancels = 0, menus = 0;
  bool down = false, secondary = false;
};

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Models the relevant Flutter 3.47.2 behavior: a held-button move can become
// down; mouse leave cancels; capture loss alone does not cancel.
LRESULT CALLBACK Receiver(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  auto* input = reinterpret_cast<Input*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (!input) return DefWindowProcW(hwnd, message, wp, lp);
  switch (message) {
    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
    case WM_MBUTTONDOWN:
    case WM_XBUTTONDOWN:
      SetCapture(hwnd);
      input->down = true;
      input->secondary = message == WM_RBUTTONDOWN;
      ++input->downs;
      return 0;
    case WM_MOUSEMOVE:
      ++input->moves;
      if ((wp & (MK_LBUTTON | MK_RBUTTON | MK_MBUTTON | MK_XBUTTON1 |
                 MK_XBUTTON2)) != 0 && !input->down) {
        input->down = true;
        input->secondary = (wp & MK_RBUTTON) != 0;
        ++input->downs;
      }
      return 0;
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
    case WM_MBUTTONUP:
    case WM_XBUTTONUP:
      ReleaseCapture();
      if (input->down && input->secondary) ++input->menus;
      input->down = false;
      ++input->ups;
      return 0;
    case WM_MOUSELEAVE:
      if (input->down) ++input->cancels;
      input->down = false;
      return 0;
    default:
      return DefWindowProcW(hwnd, message, wp, lp);
  }
}

HWND CreateReceiver(Input* input) {
  const HWND hwnd = CreateWindowW(L"CBMouseInputGuardTest", L"", 0,
                                  0, 0, 100, 100, nullptr, nullptr,
                                  GetModuleHandleW(nullptr), nullptr);
  Check(hwnd != nullptr, "Could not create test receiver");
  SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(input));
  return hwnd;
}
}  // namespace

int main() {
  try {
    WNDCLASSW wc{};
    wc.lpfnWndProc = Receiver;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"CBMouseInputGuardTest";
    Check(RegisterClassW(&wc) != 0, "Could not register test receiver");

    Input unguarded;
    const HWND baseline = CreateReceiver(&unguarded);
    SendMessageW(baseline, WM_MOUSEMOVE, MK_RBUTTON, 0);
    SendMessageW(baseline, WM_RBUTTONUP, 0, 0);
    Check(unguarded.menus == 1, "Baseline did not reproduce a stray menu");
    DestroyWindow(baseline);

    Input source, target;
    const HWND from = CreateReceiver(&source);
    const HWND to = CreateReceiver(&target);
    {
      FlutterMouseInputGuard source_guard(from);
      FlutterMouseInputGuard target_guard(to);
      SendMessageW(from, WM_LBUTTONDOWN, MK_LBUTTON, 0);
      Check(GetCapture() == from, "Source did not capture mouse");
      SetCapture(to);
      Check(source.cancels == 1 && !source.down,
            "Capture loss left the source gesture pending");
      ReleaseCapture();
      for (const WPARAM button : {MK_LBUTTON, MK_RBUTTON, MK_MBUTTON,
                                  MK_XBUTTON1, MK_XBUTTON2}) {
        SendMessageW(to, WM_MOUSEMOVE, button, 0);
      }
      SendMessageW(to, WM_RBUTTONUP, 0, 0);
      SendMessageW(from, WM_LBUTTONUP, 0, 0);
      Check(target.downs == 0 && target.ups == 0 && target.menus == 0,
            "A foreign drag reached the target as a file click");
      Check(source.ups == 0, "Canceled source press completed as a tap");

      SendMessageW(to, WM_MOUSEMOVE, MK_SHIFT, 0);
      Check(target.moves == 1, "Normal hover was blocked");
      SendMessageW(to, WM_LBUTTONDOWN, MK_LBUTTON, 0);
      SendMessageW(to, WM_MOUSEMOVE, MK_LBUTTON | MK_CONTROL, 0);
      SendMessageW(to, WM_LBUTTONUP, 0, 0);
      Check(target.downs == 1 && target.moves == 2 && target.ups == 1 &&
                target.cancels == 0,
            "Normal left drag was canceled or blocked");

      // ReleaseCapture occurs before OnPointerUp in Flutter's button handler.
      SendMessageW(to, WM_RBUTTONDOWN, MK_RBUTTON, 0);
      SendMessageW(to, WM_RBUTTONUP, 0, 0);
      Check(target.menus == 1 && target.cancels == 0,
            "A genuine right-click no longer opens the context menu");
      SendMessageW(to, WM_MBUTTONDOWN, MK_MBUTTON, 0);
      SendMessageW(to, WM_MBUTTONUP, 0, 0);
      SendMessageW(to, WM_XBUTTONDOWN, MAKEWPARAM(MK_XBUTTON1, XBUTTON1), 0);
      SendMessageW(to, WM_XBUTTONUP, MAKEWPARAM(0, XBUTTON1), 0);
      SendMessageW(to, WM_XBUTTONDOWN, MAKEWPARAM(MK_XBUTTON2, XBUTTON2), 0);
      SendMessageW(to, WM_XBUTTONUP, MAKEWPARAM(0, XBUTTON2), 0);
      Check(target.downs == 5 && target.ups == 5,
            "An auxiliary mouse button was blocked");

      // The view may be destroyed before its owning guard.
      DestroyWindow(to);
      DestroyWindow(from);
    }
    std::cout << "PASS: foreign drags blocked, capture loss canceled, normal "
                 "hover/drag/right/middle/extra clicks preserved\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
