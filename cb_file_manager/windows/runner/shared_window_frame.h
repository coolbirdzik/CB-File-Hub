#ifndef RUNNER_SHARED_WINDOW_FRAME_H_
#define RUNNER_SHARED_WINDOW_FRAME_H_

#include <windows.h>
#include <commctrl.h>

#include <algorithm>
#include <memory>

#include "custom_frame_message.h"
#include "flutter_mouse_input_guard.h"

constexpr UINT kStartSharedWindowDrag = WM_APP + 0x61;

inline void RestoreSharedWindowForDrag(HWND hwnd, POINT cursor) {
  RECT maximized{};
  if (!::IsZoomed(hwnd) || !::GetWindowRect(hwnd, &maximized)) return;

  ::ShowWindow(hwnd, SW_RESTORE);
  RECT restored{};
  if (!::GetWindowRect(hwnd, &restored) || ::IsZoomed(hwnd)) return;

  const LONG width = maximized.right - maximized.left;
  if (width <= 0) return;
  const LONG maximized_offset = std::clamp(cursor.x - maximized.left, 0L, width);
  const LONG offset_x = ::MulDiv(maximized_offset,
                                 restored.right - restored.left, width);
  const LONG offset_y = std::clamp(cursor.y - maximized.top, 0L,
                                   restored.bottom - restored.top);
  ::SetWindowPos(hwnd, nullptr, cursor.x - offset_x, cursor.y - offset_y, 0, 0,
                 SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER);
}

inline LRESULT CALLBACK SharedWindowFrameProc(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam,
                                             UINT_PTR id,
                                             DWORD_PTR mouse_input_guard) {
  if (message == kStartSharedWindowDrag) {
    POINT cursor{};
    if ((::GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0 ||
        !::GetCursorPos(&cursor)) {
      return 0;
    }
    RestoreSharedWindowForDrag(hwnd, cursor);
    // Release Flutter's capture immediately before the system takes over.
    ::ReleaseCapture();
    return ::DefWindowProcW(hwnd, WM_SYSCOMMAND, SC_MOVE | HTCAPTION,
                            MAKELPARAM(cursor.x, cursor.y));
  }
  std::unique_ptr<FlutterMouseInputGuard> guard_to_destroy;
  if (message == WM_NCDESTROY) {
    ::RemoveWindowSubclass(hwnd, SharedWindowFrameProc, id);
    guard_to_destroy.reset(
        reinterpret_cast<FlutterMouseInputGuard*>(mouse_input_guard));
  }
  // Run before the engine's plugins so window_manager's main HWND cannot
  // affect the geometry of this window.
  return DispatchCustomFrameMessage(
      hwnd, message, wparam, lparam,
      [&](LPARAM forwarded) {
        return ::DefSubclassProc(hwnd, message, wparam, forwarded);
      },
      /*custom_frame_without_caption=*/true);
}

inline bool InstallSharedWindowFrame(HWND hwnd, HWND view = nullptr) {
  const LONG_PTR style = ::GetWindowLongPtrW(hwnd, GWL_STYLE);
  const auto ex_style = static_cast<DWORD>(::GetWindowLongPtrW(hwnd, GWL_EXSTYLE));
  RECT window{};
  RECT native_frame{};
  if (!::GetWindowRect(hwnd, &window) ||
      !::AdjustWindowRectExForDpi(&native_frame, static_cast<DWORD>(style),
                                 FALSE, ex_style, ::GetDpiForWindow(hwnd))) {
    return false;
  }
  // Flutter creates the initial surface at the decorated size. Keep the
  // requested content size when replacing that frame. Reusing the decorated
  // size as the client size can leave Flutter waiting on an earlier resize.
  const LONG width =
      (window.right - window.left) - (native_frame.right - native_frame.left);
  const LONG height =
      (window.bottom - window.top) - (native_frame.bottom - native_frame.top);
  if (width <= 0 || height <= 0) return false;

  constexpr UINT_PTR kSubclassId = 1;
  auto guard = view ? std::make_unique<FlutterMouseInputGuard>(view) : nullptr;
  const auto reference = reinterpret_cast<DWORD_PTR>(guard.get());
  if (!::SetWindowSubclass(hwnd, SharedWindowFrameProc, kSubclassId,
                           reference)) {
    return false;
  }
  auto* installed_guard = guard.release();
  ::SetWindowLongPtrW(hwnd, GWL_STYLE, style & ~WS_CAPTION);
  SuppressCustomFrameBorder(hwnd);
  if (::SetWindowPos(hwnd, nullptr, 0, 0, width, height,
                     SWP_FRAMECHANGED | SWP_NOMOVE |
                         SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER)) {
    return true;
  }
  if (::RemoveWindowSubclass(hwnd, SharedWindowFrameProc, kSubclassId)) {
    delete installed_guard;
  }
  return false;
}

#endif  // RUNNER_SHARED_WINDOW_FRAME_H_
