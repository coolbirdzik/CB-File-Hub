// Standalone Win32 unit test: no Flutter engine or app E2E.
#include <windows.h>
#include <dwmapi.h>

#include <iostream>
#include <map>
#include <stdexcept>
#include <string>

// DWMWA_BORDER_COLOR is set-only: DwmGetWindowAttribute rejects it. Observe
// accepted requests while forwarding them to the real DWM on test windows.
static std::map<HWND, COLORREF> accepted_border_colors;
HRESULT WINAPI ObserveDwmSetWindowAttribute(HWND hwnd, DWORD attribute,
                                           LPCVOID value, DWORD size) {
  const HRESULT result = ::DwmSetWindowAttribute(hwnd, attribute, value, size);
  if (SUCCEEDED(result) && attribute == 34 && size == sizeof(COLORREF)) {
    accepted_border_colors[hwnd] = *static_cast<const COLORREF*>(value);
  }
  return result;
}
#define DwmSetWindowAttribute ObserveDwmSetWindowAttribute
#include "../custom_frame_message.h"
#undef DwmSetWindowAttribute
#include "../flutter_mouse_input_guard.h"

namespace {
struct Events {
  int native_paints = 0;
  int activations = 0;
  int unsafe_activations = 0;
  int unsafe_title_updates = 0;
  int sizes = 0;
  bool nested_title_update = false;
  bool reset_border_on_theme = false;
  int client_layouts = 0;
  bool refuse_resize = false;
  bool use_system_layout = false;
  bool reset_border_on_title = false;
};

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  auto* events = reinterpret_cast<Events*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (!events) return DefWindowProcW(hwnd, message, wp, lp);
  if (message == WM_NCCALCSIZE && events->use_system_layout) {
    return DefWindowProcW(hwnd, message, wp, lp);
  }
  return DispatchCustomFrameMessage(hwnd, message, wp, lp, [&](LPARAM forwarded) {
    // Represents a plugin which consumes the message before runner fallback.
    switch (message) {
      case WM_NCCALCSIZE:
        ++events->client_layouts;
        if (wp) {
          // Match window_manager's hidden-titlebar layout. It leaves an 8 px
          // non-client band which must be intercepted before plugin dispatch.
          auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(forwarded);
          params->rgrc[0].left += 8;
          params->rgrc[0].right -= 8;
          params->rgrc[0].bottom -= 8;
          return LRESULT{0};
        }
        break;
      case WM_GETMINMAXINFO:
        // window_manager answers this without touching the maximized rect.
        return LRESULT{0};
      case WM_NCHITTEST:
        if (events->refuse_resize) return LRESULT{HTNOWHERE};
        break;
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
        if (events->reset_border_on_title) {
          const COLORREF system_border = 0xFFFFFFFF;
          ObserveDwmSetWindowAttribute(hwnd, 34, &system_border,
                                       sizeof(system_border));
        }
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
      case WM_THEMECHANGED:
      case WM_DWMCOMPOSITIONCHANGED:
      case WM_DWMCOLORIZATIONCOLORCHANGED:
        if (events->reset_border_on_theme) {
          const COLORREF system_border = 0xFFFFFFFF;
          ObserveDwmSetWindowAttribute(hwnd, 34, &system_border,
                                       sizeof(system_border));
        }
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

void CheckClientAndResize(HWND hwnd, Events& events) {
  for (const RECT proposed : {RECT{-1800, -500, -1000, 100},
                              RECT{100, 80, 900, 680}}) {
    NCCALCSIZE_PARAMS params{};
    params.rgrc[0] = proposed;
    Check(SendMessageW(hwnd, WM_NCCALCSIZE, TRUE,
                       reinterpret_cast<LPARAM>(&params)) == 0 &&
              EqualRect(&params.rgrc[0], &proposed),
          "Restored window still reserves a native band around the client");
    RECT simple = proposed;
    SendMessageW(hwnd, WM_NCCALCSIZE, FALSE, reinterpret_cast<LPARAM>(&simple));
    Check(EqualRect(&simple, &proposed), "Simple layout retained a native frame");
  }
  Check(events.client_layouts == 0, "A plugin was allowed to reinsert the frame");

  // Query the actual client rectangle after Windows applies the new layout.
  SetWindowPos(hwnd, nullptr, -2000, -600, 800, 600,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  RECT client{}, window{};
  GetClientRect(hwnd, &client);
  GetWindowRect(hwnd, &window);
  POINT origin{0, 0};
  ClientToScreen(hwnd, &origin);
  Check(origin.x == window.left && origin.y == window.top &&
            client.right == window.right - window.left &&
            client.bottom == window.bottom - window.top,
        "Real HWND client does not cover the whole restored window");
  const LONG center_x = (window.left + window.right) / 2;
  const LONG center_y = (window.top + window.bottom) / 2;
  const POINT points[] = {{window.left + 1, window.top + 1},
                          {center_x, window.top + 1},
                          {window.right - 1, window.top + 1},
                          {window.left + 1, center_y},
                          {window.right - 1, center_y},
                          {window.left + 1, window.bottom - 1},
                          {center_x, window.bottom - 1},
                          {window.right - 1, window.bottom - 1},
                          {center_x, center_y}};
  const LRESULT hits[] = {HTTOPLEFT, HTTOP, HTTOPRIGHT, HTLEFT, HTRIGHT,
                         HTBOTTOMLEFT, HTBOTTOM, HTBOTTOMRIGHT, HTCLIENT};
  for (int i = 0; i < 9; ++i) {
    Check(SendMessageW(hwnd, WM_NCHITTEST, 0,
                       MAKELPARAM(points[i].x, points[i].y)) == hits[i],
          "Borderless window lost an edge/corner resize target");
  }
  WNDCLASSW child_class{};
  child_class.lpfnWndProc = DefWindowProcW;
  child_class.hInstance = GetModuleHandleW(nullptr);
  child_class.lpszClassName = L"CBEmbeddedFrameTest";
  Check(RegisterClassW(&child_class) != 0, "Could not register embedded view");
  const HWND view = CreateWindowExW(0, child_class.lpszClassName, L"", WS_CHILD, 0, 0,
                                     800, 600, hwnd, nullptr,
                                     GetModuleHandleW(nullptr), nullptr);
  Check(view != nullptr, "Could not create an embedded test view");
  FlutterMouseInputGuard view_guard(view);
  for (int i = 0; i < 9; ++i) {
    Check(SendMessageW(view, WM_NCHITTEST, 0,
                       MAKELPARAM(points[i].x, points[i].y)) ==
              (i == 8 ? HTCLIENT : HTTRANSPARENT),
          "Embedded view swallowed a root resize edge or blocked its content");
  }
  events.refuse_resize = true;
  Check(SendMessageW(hwnd, WM_NCHITTEST, 0,
                     MAKELPARAM(window.left + 1, center_y)) == HTNOWHERE,
        "Custom resize overrode the plugin's non-resizable policy");
  Check(SendMessageW(view, WM_NCHITTEST, 0,
                     MAKELPARAM(window.left + 1, center_y)) == HTCLIENT,
        "A non-resizable view lost normal edge input");
  events.refuse_resize = false;

  // A maximized HWND can overhang its monitor; keep content in the work area.
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor);
  const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
  SetWindowLongPtrW(hwnd, GWL_STYLE, style | WS_MAXIMIZE);
  NCCALCSIZE_PARAMS max_params{};
  max_params.rgrc[0] = monitor.rcWork;
  InflateRect(&max_params.rgrc[0], 16, 16);
  SendMessageW(hwnd, WM_NCCALCSIZE, TRUE,
               reinterpret_cast<LPARAM>(&max_params));
  Check(EqualRect(&max_params.rgrc[0], &monitor.rcWork),
        "Maximized client does not respect the monitor work area");
  Check(SendMessageW(hwnd, WM_NCHITTEST, 0,
                     MAKELPARAM(window.left + 1, center_y)) == HTCLIENT,
        "A maximized window still exposes resize edges");
  SetWindowLongPtrW(hwnd, GWL_STYLE, style);
  DestroyWindow(view);
}

// The kernel lays a maximized window out as the work area plus its resize
// frame; the rect must be the work area itself or the glass paints onto the
// neighbouring monitor.
void CheckMaximizedBounds() {
  Events events;
  const HWND hwnd = CreateReceiver(&events);
  const RECT normal{100, 80, 1100, 730};
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  GetMonitorInfoW(MonitorFromRect(&normal, MONITOR_DEFAULTTONEAREST), &monitor);
  const RECT work = monitor.rcWork;
  auto bounds = [&] {
    RECT rect{};
    GetWindowRect(hwnd, &rect);
    return rect;
  };
  auto place_normal = [&] {
    ShowWindow(hwnd, SW_RESTORE);
    SetWindowPos(hwnd, nullptr, normal.left, normal.top, normal.right - normal.left,
                 normal.bottom - normal.top, SWP_NOZORDER | SWP_NOACTIVATE);
  };
  place_normal();
  const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);

  const int sizes_before = events.sizes;
  ShowWindow(hwnd, SW_SHOWMAXIMIZED);
  Check(IsZoomed(hwnd) && (GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_MAXIMIZE) != 0,
        "Could not maximize the native test window");
  RECT maximized = bounds();
  Check(EqualRect(&maximized, &work),
        "A maximized window overhangs its monitor work area");
  Check(events.sizes > sizes_before,
        "Maximizing did not report a size change to plugins");
  Check(GetPropW(hwnd, kMaximizeHiddenProp) == nullptr,
        "The maximized bit stayed hidden after a placement");

  // Every tab switch refreshes the frame; it must not nudge the window.
  for (int i = 0; i < 20; ++i) {
    SetWindowTextW(hwnd, L"CB File Hub - tab");
    maximized = bounds();
    Check(EqualRect(&maximized, &work) && IsZoomed(hwnd),
          "A title update moved a maximized window");
  }

  // Taskbar minimize and restore of a maximized window.
  ShowWindow(hwnd, SW_MINIMIZE);
  Check(IsIconic(hwnd), "A maximized window could not minimize");
  ShowWindow(hwnd, SW_RESTORE);
  maximized = bounds();
  Check(IsZoomed(hwnd) && EqualRect(&maximized, &work),
        "Restoring from minimize lost the maximized work-area bounds");

  // Leaving the maximized state returns to the rect from before maximizing,
  // also after a minimize: the kernel stores the work area there otherwise.
  ShowWindow(hwnd, SW_RESTORE);
  RECT restored = bounds();
  Check(!IsZoomed(hwnd) && EqualRect(&restored, &normal),
        "Restore did not return to the previous bounds");

  // A window without WS_THICKFRAME and WS_MAXIMIZEBOX is full screen: not fitted.
  place_normal();
  SetWindowLongPtrW(hwnd, GWL_STYLE, style & ~(WS_THICKFRAME | WS_MAXIMIZEBOX));
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  ShowWindow(hwnd, SW_SHOWMAXIMIZED);
  Check(GetPropW(hwnd, kMaximizeHiddenProp) == nullptr && IsZoomed(hwnd),
        "A full-screen style window was fitted to the work area");
  SetWindowPos(hwnd, nullptr, monitor.rcMonitor.left, monitor.rcMonitor.top,
               monitor.rcMonitor.right - monitor.rcMonitor.left,
               monitor.rcMonitor.bottom - monitor.rcMonitor.top,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  RECT full = bounds();
  Check(EqualRect(&full, &monitor.rcMonitor),
        "A full-screen style window did not cover its monitor");
  // Leaving full screen restores the style and refreshes the frame, as
  // window_manager does, and must land on the work area, not the monitor.
  SetWindowLongPtrW(hwnd, GWL_STYLE, style | WS_MAXIMIZE);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  RECT left_full = bounds();
  Check(IsZoomed(hwnd) && EqualRect(&left_full, &work),
        "Leaving full screen left a maximized window off its work area");
  SetWindowLongPtrW(hwnd, GWL_STYLE, style);
  DestroyWindow(hwnd);
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
    CheckClientAndResize(windows[0], first);
    CheckMaximizedBounds();
    first.sizes = 0;
    const COLORREF visible_border = RGB(255, 0, 0);
    const bool supports_border_color = SUCCEEDED(ObserveDwmSetWindowAttribute(
        windows[0], 34, &visible_border, sizeof(visible_border)));
    if (supports_border_color) {
      ObserveDwmSetWindowAttribute(windows[1], 34, &visible_border,
                                   sizeof(visible_border));
    }
    for (const HWND hwnd : windows) {
      SetWindowLongPtrW(hwnd, GWL_STYLE,
                        GetWindowLongPtrW(hwnd, GWL_STYLE) | WS_VISIBLE);
    }
    // Tab selection updates the taskbar title without a focus/theme message.
    // Assert after each title, not after an activation which would mask this.
    first.reset_border_on_title = true;
    for (int i = 0; i < 100; ++i) {
      // Seed a real cached system frame, then restore our message handler.
      // The title update must recover the client geometry without refocusing.
      first.use_system_layout = true;
      SetWindowPos(windows[0], nullptr, 0, 0, 0, 0,
                   SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_FRAMECHANGED);
      first.use_system_layout = false;
      const LONG_PTR style_before = GetWindowLongPtrW(windows[0], GWL_STYLE);
      RECT bounds_before{}, bounds_after{};
      GetWindowRect(windows[0], &bounds_before);
      const auto title = L"CB File Hub - Tab " + std::to_wstring(i);
      SetWindowTextW(windows[0], title.c_str());
      GetWindowRect(windows[0], &bounds_after);
      RECT client{};
      POINT origin{};
      GetClientRect(windows[0], &client);
      ClientToScreen(windows[0], &origin);
      Check(origin.x == bounds_after.left && origin.y == bounds_after.top &&
                client.right == bounds_after.right - bounds_after.left &&
                client.bottom == bounds_after.bottom - bounds_after.top,
            "Tab title change left a cached OS frame around the client");
      Check(GetWindowLongPtrW(windows[0], GWL_STYLE) == style_before &&
                EqualRect(&bounds_before, &bounds_after),
            "Tab title change moved/resized the window or changed its style");
      if (supports_border_color) {
        Check(accepted_border_colors[windows[0]] == 0xFFFFFFFE,
              "Tab title change restored the DWM outline without refocusing");
      }
    }
    first.reset_border_on_title = false;
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
    if (supports_border_color) {
      for (const HWND hwnd : windows) {
        Check(accepted_border_colors[hwnd] == 0xFFFFFFFE,
              "DWM outline remained visible after activation");
      }
      first.reset_border_on_theme = true;
      for (const UINT message : {WM_THEMECHANGED, WM_DWMCOMPOSITIONCHANGED,
                                 WM_DWMCOLORIZATIONCOLORCHANGED}) {
        SendMessageW(windows[0], message, 0, 0);
        Check(accepted_border_colors[windows[0]] == 0xFFFFFFFE,
              "Theme/composition change restored the native outline");
      }
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
    const int sizes_before = first.sizes;
    SendMessageW(windows[0], WM_SIZE, SIZE_RESTORED, MAKELPARAM(320, 200));
    Check(first.sizes == sizes_before + 1, "Normal resize messages were blocked");

    // Hidden spare windows remain hidden after updating their tab title.
    SetWindowLongPtrW(windows[1], GWL_STYLE,
                      GetWindowLongPtrW(windows[1], GWL_STYLE) & ~WS_VISIBLE);
    SetWindowTextW(windows[1], L"Spare");
    Check(!IsWindowVisible(windows[1]), "Title update revealed a spare window");
    Events minimized_events;
    const HWND minimized = CreateReceiver(&minimized_events);
    ShowWindow(minimized, SW_SHOWMINNOACTIVE);
    Check(IsIconic(minimized), "Could not minimize the native test window");
    SetWindowTextW(minimized, L"CB File Hub - Background tab");
    SendMessageW(minimized, WM_SETICON, ICON_SMALL, 0);
    Check(IsIconic(minimized), "Title/icon update restored a minimized window");
    DestroyWindow(minimized);
    // Fullscreen (no WS_CAPTION) keeps its existing message handling.
    SetWindowLongPtrW(windows[1], GWL_STYLE,
                      GetWindowLongPtrW(windows[1], GWL_STYLE) & ~WS_CAPTION);
    SendMessageW(windows[1], WM_NCPAINT, 1, 0);
    Check(second.native_paints == 1, "Fullscreen dispatch was changed");
    for (const HWND hwnd : windows) DestroyWindow(hwnd);
    std::cout << "PASS: real client fills window, all 8 resize grips work through "
                 "embedded view, maximized window and client stay in the "
                 "work area; "
                 "100 title-only tab switches refresh the custom frame; "
                 "caption paints blocked before plugins across 200 "
                 "merge cycles; focus/title/resize/spare state preserved; "
              << (supports_border_color ? "DWM outline stays suppressed\n"
                                        : "border color unsupported on this OS\n");
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
