#ifndef RUNNER_CUSTOM_FRAME_MESSAGE_H_
#define RUNNER_CUSTOM_FRAME_MESSAGE_H_

#include <windows.h>

// Wrap the complete dispatch, including plugin delegates. A delegate can call
// DefWindowProc itself, so guarding only the runner's fallback is too late.
template <typename Dispatch>
LRESULT DispatchCustomFrameMessage(HWND hwnd, UINT message, WPARAM /*wparam*/,
                                   LPARAM lparam, Dispatch&& dispatch) {
  const LONG_PTR style = ::GetWindowLongPtrW(hwnd, GWL_STYLE);
  if ((style & WS_CAPTION) != WS_CAPTION) return dispatch(lparam);

  switch (message) {
    case WM_NCPAINT:
    case 0x00AE:  // WM_NCUAHDRAWCAPTION
    case 0x00AF:  // WM_NCUAHDRAWFRAME
      // Backdrop reapplication uses RedrawWindow(RDW_FRAME). Letting that
      // reach DefWindowProc paints a native caption over our transparent tabs,
      // even though WM_NCCALCSIZE has removed the caption's layout space.
      return 0;
    case WM_NCACTIVATE:
      // Preserve focus/blur notifications in plugins, but ask DefWindowProc
      // to update activation without repainting the non-client area.
      return dispatch(-1);
    case WM_SETTEXT:
    case WM_SETICON: {
      if ((style & WS_VISIBLE) == 0) return dispatch(lparam);
      // DefWindowProc draws a caption while setting text/icons. Suppress that
      // synchronous draw across plugin dispatch as well as the fallback.
      ::SetWindowLongPtrW(hwnd, GWL_STYLE, style & ~WS_VISIBLE);
      const LRESULT result = dispatch(lparam);
      if (::IsWindow(hwnd)) {
        // Keep any unrelated style changes made by a downstream handler.
        ::SetWindowLongPtrW(hwnd, GWL_STYLE,
                            ::GetWindowLongPtrW(hwnd, GWL_STYLE) | WS_VISIBLE);
      }
      return result;
    }
    default:
      return dispatch(lparam);
  }
}

#endif  // RUNNER_CUSTOM_FRAME_MESSAGE_H_
