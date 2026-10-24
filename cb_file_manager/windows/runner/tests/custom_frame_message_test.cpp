// Standalone Win32 unit test: no Flutter engine or app E2E.
#include "../custom_frame_message.h"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {
struct Events {
  int native_paints = 0;
  int activations = 0;
  int unsafe_activations = 0;
  int unsafe_title_updates = 0;
  int sizes = 0;
  bool nested_title_update = false;
};

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  auto* events = reinterpret_cast<Events*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (!events) return DefWindowProcW(hwnd, message, wp, lp);
  return DispatchCustomFrameMessage(hwnd, message, wp, lp, [&](LPARAM forwarded) {
    // Represents a plugin which consumes the message before runner fallback.
    switch (message) {
      case WM_NCPAINT:
      case 0x00AE:
      case 0x00AF:
        ++events->native_paints;
        return LRESULT{0};
      case WM_NCACTIVATE:
        ++events->activations;
        if (forwarded != -1) ++events->unsafe_activations;
        return LRESULT{TRUE};
      case WM_SETTEXT:
      case WM_SETICON:
        if ((GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_VISIBLE) != 0)
          ++events->unsafe_title_updates;
        if (message == WM_SETTEXT && events->nested_title_update) {
          events->nested_title_update = false;
          SendMessageW(hwnd, WM_SETICON, ICON_SMALL, 0);
          if ((GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_VISIBLE) != 0)
            ++events->unsafe_title_updates;
          // A downstream style update must survive the redraw lock.
          SetWindowLongPtrW(hwnd, GWL_STYLE,
                            GetWindowLongPtrW(hwnd, GWL_STYLE) | WS_DISABLED);
        }
        break;
      case WM_SIZE:
        ++events->sizes;
        break;
      default:
        break;
    }
    return DefWindowProcW(hwnd, message, wp, forwarded);
  });
}

HWND CreateReceiver(Events* events) {
  const HWND hwnd = CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L"CBFrameMessageTest", L"Before",
      WS_OVERLAPPEDWINDOW, -32000, -32000, 320, 200,
      nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  Check(hwnd != nullptr, "Could not create native test window");
  SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(events));
  return hwnd;
}
}  // namespace

int main() {
  try {
    WNDCLASSW wc{};
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"CBFrameMessageTest";
    Check(RegisterClassW(&wc) != 0, "Could not register test window");
    Events first, second;
    const HWND windows[] = {CreateReceiver(&first), CreateReceiver(&second)};
    for (const HWND hwnd : windows) {
      SetWindowLongPtrW(hwnd, GWL_STYLE,
                        GetWindowLongPtrW(hwnd, GWL_STYLE) | WS_VISIBLE);
    }
    // Repeated merge-like activation/title/frame redraws in both directions.
    for (int i = 0; i < 100; ++i) {
      for (const HWND hwnd : windows) {
        SendMessageW(hwnd, WM_NCACTIVATE, i % 2, 0);
        SetWindowTextW(hwnd, L"CB File Hub - Merged tab");
        SendMessageW(hwnd, WM_NCPAINT, 1, 0);
        SendMessageW(hwnd, 0x00AE, 0, 0);
        SendMessageW(hwnd, 0x00AF, 0, 0);
      }
    }
    for (Events* events : {&first, &second}) {
      Check(events->native_paints == 0, "Native caption paint reached a plugin");
      Check(events->activations == 100 && events->unsafe_activations == 0,
            "Focus notifications were lost or allowed native repaint");
      Check(events->unsafe_title_updates == 0,
            "Title update was drawable inside plugin dispatch");
    }
    wchar_t title[100]{};
    GetWindowTextW(windows[0], title, 100);
    Check(std::wstring(title) == L"CB File Hub - Merged tab",
          "Native taskbar title no longer updates");

    first.nested_title_update = true;
    SetWindowTextW(windows[0], L"Nested update");
    Check(first.unsafe_title_updates == 0, "Nested update exposed the caption");
    const LONG_PTR style = GetWindowLongPtrW(windows[0], GWL_STYLE);
    Check((style & (WS_VISIBLE | WS_DISABLED)) == (WS_VISIBLE | WS_DISABLED),
          "Redraw lock lost visibility or a downstream style change");
    SendMessageW(windows[0], WM_SIZE, SIZE_RESTORED, MAKELPARAM(320, 200));
    Check(first.sizes == 1, "Normal resize messages were blocked");

    // Hidden spare windows remain hidden after updating their tab title.
    SetWindowLongPtrW(windows[1], GWL_STYLE,
                      GetWindowLongPtrW(windows[1], GWL_STYLE) & ~WS_VISIBLE);
    SetWindowTextW(windows[1], L"Spare");
    Check(!IsWindowVisible(windows[1]), "Title update revealed a spare window");
    // Fullscreen (no WS_CAPTION) keeps its existing message handling.
    SetWindowLongPtrW(windows[1], GWL_STYLE,
                      GetWindowLongPtrW(windows[1], GWL_STYLE) & ~WS_CAPTION);
    SendMessageW(windows[1], WM_NCPAINT, 1, 0);
    Check(second.native_paints == 1, "Fullscreen dispatch was changed");
    for (const HWND hwnd : windows) DestroyWindow(hwnd);
    std::cout << "PASS: caption paints blocked before plugins across 200 "
                 "merge cycles; focus/title/resize/spare state preserved\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
