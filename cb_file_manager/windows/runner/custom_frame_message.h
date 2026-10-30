#ifndef RUNNER_CUSTOM_FRAME_MESSAGE_H_
#define RUNNER_CUSTOM_FRAME_MESSAGE_H_

#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>

#include <map>

// Hiding the caption does not hide Windows 11's DWM outline. Keep the native
// resize frame, shadow and rounded corners, but leave all visible chrome to
// Flutter. Older Windows versions simply reject this optional attribute.
inline void SuppressCustomFrameBorder(HWND hwnd) {
  constexpr DWORD kDwmwaBorderColor = 34;
  constexpr COLORREF kNoBorder = 0xFFFFFFFE;  // DWMWA_COLOR_NONE
  ::DwmSetWindowAttribute(hwnd, kDwmwaBorderColor, &kNoBorder, sizeof(kNoBorder));
}

inline LRESULT CustomFrameResizeHitTest(HWND hwnd, LPARAM point,
                                        LRESULT fallback) {
  if ((::GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_THICKFRAME) == 0 ||
      ::IsZoomed(hwnd) || ::IsIconic(hwnd)) return fallback;
  RECT bounds{};
  if (!::GetWindowRect(hwnd, &bounds)) return fallback;
  const POINT cursor{GET_X_LPARAM(point), GET_Y_LPARAM(point)};
  if (!::PtInRect(&bounds, cursor)) return fallback;
  const UINT dpi = ::GetDpiForWindow(hwnd);
  const int padded = ::GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int width = ::GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + padded;
  const int height = ::GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padded;
  const bool left = cursor.x < bounds.left + width;
  const bool right = cursor.x >= bounds.right - width;
  const bool top = cursor.y < bounds.top + height;
  const bool bottom = cursor.y >= bounds.bottom - height;
  if (top) return left ? HTTOPLEFT : right ? HTTOPRIGHT : HTTOP;
  if (bottom) return left ? HTBOTTOMLEFT : right ? HTBOTTOMRIGHT : HTBOTTOM;
  if (left) return HTLEFT;
  if (right) return HTRIGHT;
  return fallback;
}

// Windows lays a maximized WS_THICKFRAME window out as the work area plus its
// resize frame on every side. WM_NCCALCSIZE keeps our client inside the work
// area, but the DWM glass sheet still paints that overhang onto an adjacent
// monitor. The kernel adds the frame after WM_WINDOWPOSCHANGING, keyed on the
// window's WS_MAXIMIZE bit, and window_manager leaves WM_GETMINMAXINFO alone,
// so a rect set any other way is discarded. Hide the bit from the kernel for
// one placement and restore it before the default handler derives WM_SIZE from
// it, so plugins still see the window maximize. window_manager's fullscreen
// drops both WS_THICKFRAME and WS_MAXIMIZEBOX and is left alone;
// setResizable(false) drops only the former and must still fit.
constexpr UINT kRestoreMaximizeMessage = WM_APP + 0x47;
constexpr wchar_t kMaximizeHiddenProp[] = L"CBFileHub.MaximizeHidden";

constexpr UINT kSwpStateChanged = 0x8000;

// The restore rect of each window while it is maximized. A placement made with
// the bit hidden looks like a normal window's to the kernel, which then stores
// the work area as the restore rect; it is put back on leaving the state.
inline std::map<HWND, RECT>& SavedRestoreRects() {
  static std::map<HWND, RECT> rects;
  return rects;
}

inline bool WorkAreaOf(const RECT& bounds, RECT* work) {
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!::GetMonitorInfoW(::MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST),
                         &monitor)) {
    return false;
  }
  *work = monitor.rcWork;
  return true;
}

// Leaving the maximized state: the kernel proposes the work area it stored as
// the restore rect. Replace it with the rect saved on entering.
inline void RestoreSavedRect(HWND hwnd, WINDOWPOS* pos) {
  auto& saved = SavedRestoreRects();
  const auto found = saved.find(hwnd);
  if (!pos || found == saved.end() || (pos->flags & kSwpStateChanged) == 0 ||
      ::IsZoomed(hwnd) || ::IsIconic(hwnd)) {
    return;
  }
  const RECT proposed = {pos->x, pos->y, pos->x + pos->cx, pos->y + pos->cy};
  RECT work{};
  if (WorkAreaOf(proposed, &work) && ::EqualRect(&proposed, &work)) {
    pos->x = found->second.left;
    pos->y = found->second.top;
    pos->cx = found->second.right - found->second.left;
    pos->cy = found->second.bottom - found->second.top;
    pos->flags &= ~(SWP_NOMOVE | SWP_NOSIZE);
  }
  saved.erase(found);
}

// Placements that leave a maximized window on its work area are not touched:
// every tab switch refreshes the frame that way.
inline void FitMaximizedPlacement(HWND hwnd, WINDOWPOS* pos) {
  if (!pos || ::GetPropW(hwnd, kMaximizeHiddenProp) ||
      (::GetWindowLongPtrW(hwnd, GWL_STYLE) &
       (WS_THICKFRAME | WS_MAXIMIZEBOX)) == 0 ||
      !::IsZoomed(hwnd) || ::IsIconic(hwnd)) {
    return;
  }
  RECT proposed{};
  if (!::GetWindowRect(hwnd, &proposed)) return;
  if ((pos->flags & SWP_NOMOVE) == 0) {
    ::OffsetRect(&proposed, pos->x - proposed.left, pos->y - proposed.top);
  }
  if ((pos->flags & SWP_NOSIZE) == 0) {
    proposed.right = proposed.left + pos->cx;
    proposed.bottom = proposed.top + pos->cy;
  }
  RECT work{};
  if (!WorkAreaOf(proposed, &work) || ::EqualRect(&proposed, &work)) return;
  pos->x = work.left;
  pos->y = work.top;
  pos->cx = work.right - work.left;
  pos->cy = work.bottom - work.top;
  pos->flags &= ~(SWP_NOMOVE | SWP_NOSIZE);
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (::GetWindowPlacement(hwnd, &placement)) {
    SavedRestoreRects().emplace(hwnd, placement.rcNormalPosition);
  }
  ::SetPropW(hwnd, kMaximizeHiddenProp, reinterpret_cast<HANDLE>(1));
  ::SetWindowLongPtrW(hwnd, GWL_STYLE,
                      ::GetWindowLongPtrW(hwnd, GWL_STYLE) & ~WS_MAXIMIZE);
  // A placement that changes nothing sends no WM_WINDOWPOSCHANGED.
  ::PostMessageW(hwnd, kRestoreMaximizeMessage, 0, 0);
}

inline void RestoreMaximizeBit(HWND hwnd) {
  if (!::GetPropW(hwnd, kMaximizeHiddenProp)) return;
  ::RemovePropW(hwnd, kMaximizeHiddenProp);
  ::SetWindowLongPtrW(hwnd, GWL_STYLE,
                      ::GetWindowLongPtrW(hwnd, GWL_STYLE) | WS_MAXIMIZE);
}

// Wrap the complete dispatch, including plugin delegates. A delegate can call
// DefWindowProc itself, so guarding only the runner's fallback is too late.
template <typename Dispatch>
LRESULT DispatchCustomFrameMessage(HWND hwnd, UINT message, WPARAM /*wparam*/,
                                   LPARAM lparam, Dispatch&& dispatch) {
  const LONG_PTR style = ::GetWindowLongPtrW(hwnd, GWL_STYLE);
  if ((style & WS_CAPTION) != WS_CAPTION) return dispatch(lparam);

  switch (message) {
    case WM_NCCALCSIZE: {
      // Own this before plugins: window_manager's hidden titlebar reserves
      // an 8 px non-client band on the sides/bottom. Flutter must fill it too.
      // RECT and NCCALCSIZE_PARAMS both start with the proposed window rect.
      auto* client = reinterpret_cast<RECT*>(lparam);
      if (client && ::IsZoomed(hwnd)) {
        MONITORINFO monitor{};
        monitor.cbSize = sizeof(monitor);
        if (::GetMonitorInfoW(::MonitorFromRect(client, MONITOR_DEFAULTTONEAREST),
                              &monitor)) {
          RECT visible{};
          if (::IntersectRect(&visible, client, &monitor.rcWork)) *client = visible;
        }
      }
      return 0;
    }
    case WM_WINDOWPOSCHANGING: {
      // After plugins and DefWindowProc, which applies min/max track sizes.
      const LRESULT result = dispatch(lparam);
      auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
      RestoreSavedRect(hwnd, pos);
      FitMaximizedPlacement(hwnd, pos);
      return result;
    }
    case WM_NCDESTROY:
      SavedRestoreRects().erase(hwnd);
      return dispatch(lparam);
    case WM_WINDOWPOSCHANGED:
      RestoreMaximizeBit(hwnd);
      return dispatch(lparam);
    case kRestoreMaximizeMessage:
      RestoreMaximizeBit(hwnd);
      return 0;
    case WM_NCHITTEST: {
      const LRESULT hit = dispatch(lparam);
      // Respect a plugin's non-resizable policy and explicit non-client hits.
      return hit == HTCLIENT || hit == HTBORDER
                 ? CustomFrameResizeHitTest(hwnd, lparam, hit) : hit;
    }
    case WM_NCPAINT:
    case 0x00AE:  // WM_NCUAHDRAWCAPTION
    case 0x00AF:  // WM_NCUAHDRAWFRAME
      // Backdrop reapplication uses RedrawWindow(RDW_FRAME). Letting that
      // reach DefWindowProc paints a native caption over our transparent tabs,
      // even though WM_NCCALCSIZE has removed the caption's layout space.
      return 0;
    case WM_NCACTIVATE: {
      // Preserve focus/blur notifications in plugins, but ask DefWindowProc
      // to update activation without repainting the non-client area.
      const LRESULT result = dispatch(-1);
      SuppressCustomFrameBorder(hwnd);
      return result;
    }
    case WM_THEMECHANGED:
    case WM_DWMCOMPOSITIONCHANGED:
    case WM_DWMCOLORIZATIONCOLORCHANGED: {
      const LRESULT result = dispatch(lparam);
      // A plugin or DWM can restore system chrome while changing the backdrop.
      SuppressCustomFrameBorder(hwnd);
      return result;
    }
    case WM_SETTEXT:
    case WM_SETICON: {
      if ((style & WS_VISIBLE) == 0) {
        const LRESULT result = dispatch(lparam);
        if (::IsWindow(hwnd)) SuppressCustomFrameBorder(hwnd);
        return result;
      }
      // DefWindowProc draws a caption while setting text/icons. Suppress that
      // synchronous draw across plugin dispatch as well as the fallback.
      ::SetWindowLongPtrW(hwnd, GWL_STYLE, style & ~WS_VISIBLE);
      const LRESULT result = dispatch(lparam);
      if (::IsWindow(hwnd)) {
        // Keep any unrelated style changes made by a downstream handler.
        ::SetWindowLongPtrW(hwnd, GWL_STYLE,
                            ::GetWindowLongPtrW(hwnd, GWL_STYLE) | WS_VISIBLE);
        // A tab title changes without activation. Restoring WS_VISIBLE can
        // leave DWM's cached non-client frame active until the next focus or
        // resize. Recalculate our client now, then restore the border policy.
        ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                       SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                           SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        SuppressCustomFrameBorder(hwnd);
        // Replace any caption pixels drawn by DefWindowProc with client
        // content; do not request another non-client/frame repaint.
        ::RedrawWindow(hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_ALLCHILDREN);
      }
      return result;
    }
    default:
      return dispatch(lparam);
  }
}

#endif  // RUNNER_CUSTOM_FRAME_MESSAGE_H_
