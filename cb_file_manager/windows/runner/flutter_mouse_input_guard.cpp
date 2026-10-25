#include "flutter_mouse_input_guard.h"

namespace {
constexpr WPARAM kMouseButtons =
    MK_LBUTTON | MK_RBUTTON | MK_MBUTTON | MK_XBUTTON1 | MK_XBUTTON2;

WPARAM ButtonForMessage(UINT message, WPARAM wparam) {
  switch (message) {
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
      return MK_LBUTTON;
    case WM_RBUTTONDOWN:
    case WM_RBUTTONUP:
      return MK_RBUTTON;
    case WM_MBUTTONDOWN:
    case WM_MBUTTONUP:
      return MK_MBUTTON;
    case WM_XBUTTONDOWN:
    case WM_XBUTTONUP:
      return GET_XBUTTON_WPARAM(wparam) == XBUTTON1 ? MK_XBUTTON1 : MK_XBUTTON2;
    default:
      return 0;
  }
}

bool IsMouseDown(UINT message) {
  return message == WM_LBUTTONDOWN || message == WM_RBUTTONDOWN ||
         message == WM_MBUTTONDOWN || message == WM_XBUTTONDOWN;
}

bool IsMouseUp(UINT message) {
  return message == WM_LBUTTONUP || message == WM_RBUTTONUP ||
         message == WM_MBUTTONUP || message == WM_XBUTTONUP;
}
}  // namespace

FlutterMouseInputGuard::FlutterMouseInputGuard(HWND view) : view_(view) {
  ::SetWindowSubclass(view_, WindowProc, reinterpret_cast<UINT_PTR>(this),
                      reinterpret_cast<DWORD_PTR>(this));
}

FlutterMouseInputGuard::~FlutterMouseInputGuard() {
  if (view_) {
    ::RemoveWindowSubclass(view_, WindowProc, reinterpret_cast<UINT_PTR>(this));
  }
}

LRESULT CALLBACK FlutterMouseInputGuard::WindowProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR reference) {
  auto* guard = reinterpret_cast<FlutterMouseInputGuard*>(reference);
  if (message == WM_NCDESTROY) {
    guard->view_ = nullptr;
    ::RemoveWindowSubclass(hwnd, WindowProc, subclass_id);
    return ::DefSubclassProc(hwnd, message, wparam, lparam);
  }

  if (message == WM_NCHITTEST) {
    // The view now covers the entire client, including the resize grips. Let
    // Windows reach the top-level HWND at its edges instead of resizing the
    // Flutter child or swallowing the parent's non-client mouse messages.
    const HWND root = ::GetAncestor(hwnd, GA_ROOT);
    if (root && root != hwnd) {
      const LRESULT hit = ::SendMessageW(root, message, wparam, lparam);
      if (hit >= HTLEFT && hit <= HTBOTTOMRIGHT) return HTTRANSPARENT;
    }
  }

  // Flutter handles touch/pen through WM_POINTER. Leave their promoted mouse
  // messages alone; only physical mouse gestures have capture tracked here.
  const bool promoted =
      (::GetMessageExtraInfo() & 0xFFFFFF00) == 0xFF515700;
  if (!promoted) {
    if (IsMouseDown(message)) {
      guard->pressed_buttons_ |= ButtonForMessage(message, wparam);
    } else if (IsMouseUp(message)) {
      const WPARAM button = ButtonForMessage(message, wparam);
      if ((guard->pressed_buttons_ & button) == 0) return 0;
      // Flutter releases capture synchronously inside its button-up handler.
      // Clear first so that normal release does not cancel a legitimate tap.
      guard->pressed_buttons_ &= ~button;
    } else if (message == WM_MOUSEMOVE && (wparam & kMouseButtons) != 0 &&
               ::GetCapture() != hwnd) {
      // Flutter 3.47.2 synthesizes a down from this move, even though this
      // view never received the press. Do not let a tab drag hit file gestures.
      return 0;
    }
  }

  if (message == WM_CAPTURECHANGED &&
      reinterpret_cast<HWND>(lparam) != hwnd && guard->pressed_buttons_ != 0) {
    guard->pressed_buttons_ = 0;
    // The engine does not cancel on capture loss. Its mouse-leave path removes
    // the pointer and synthesizes a cancel if down, rather than completing a
    // tap/long press later when this window is shown again.
    ::DefSubclassProc(hwnd, WM_MOUSELEAVE, 0, 0);
  } else if (message == WM_MOUSELEAVE) {
    guard->pressed_buttons_ = 0;
  }
  return ::DefSubclassProc(hwnd, message, wparam, lparam);
}
