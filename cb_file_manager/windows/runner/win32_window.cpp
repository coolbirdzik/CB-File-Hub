#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace
{

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

  constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

  /// Registry key for app theme preference.
  ///
  /// A value of 0 indicates apps should use dark mode. A non-zero or missing
  /// value indicates apps should use light mode.
  constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
  constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

  // The number of Win32Window objects that currently exist.
  static int g_active_window_count = 0;

  using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

  // Scale helper to convert logical scaler values to physical using passed in
  // scale factor
  int Scale(int source, double scale_factor)
  {
    return static_cast<int>(source * scale_factor);
  }

  // Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
  // This API is only needed for PerMonitor V1 awareness mode.
  void EnableFullDpiSupportIfAvailable(HWND hwnd)
  {
    HMODULE user32_module = LoadLibraryA("User32.dll");
    if (!user32_module)
    {
      return;
    }
    auto enable_non_client_dpi_scaling =
        reinterpret_cast<EnableNonClientDpiScaling *>(
            GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
    if (enable_non_client_dpi_scaling != nullptr)
    {
      enable_non_client_dpi_scaling(hwnd);
    }
    FreeLibrary(user32_module);
  }

} // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar
{
public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar *GetInstance()
  {
    if (!instance_)
    {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t *GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar *instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar *WindowClassRegistrar::instance_ = nullptr;

const wchar_t *WindowClassRegistrar::GetWindowClass()
{
  if (!class_registered_)
  {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass()
{
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window()
{
  ++g_active_window_count;
}

Win32Window::~Win32Window()
{
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring &title,
                         const Point &origin,
                         const Size &size)
{
  Destroy();

  const wchar_t *window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  // Get the monitor information to properly position the window
  MONITORINFO monitor_info = {0};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(monitor, &monitor_info))
  {
    return false;
  }

  // Calculate window size with respect to work area (excludes taskbar)
  // This ensures the window doesn't overflow the usable screen area
  int adjusted_width = size.width;
  int adjusted_height = size.height;

  // Calculate proper positioning - default to work area if needed
  int x_pos = origin.x;
  int y_pos = origin.y;

  if (origin.x == 0 && origin.y == 0)
  {
    // Center in the work area if no specific position is specified
    x_pos = monitor_info.rcWork.left +
            (monitor_info.rcWork.right - monitor_info.rcWork.left - adjusted_width) / 2;
    y_pos = monitor_info.rcWork.top +
            (monitor_info.rcWork.bottom - monitor_info.rcWork.top - adjusted_height) / 2;
  }

  // Create a standard overlapped window with proper styles
  HWND window = CreateWindow(
      window_class,
      title.c_str(),
      WS_OVERLAPPEDWINDOW,
      Scale(x_pos, scale_factor),
      Scale(y_pos, scale_factor),
      Scale(adjusted_width, scale_factor),
      Scale(adjusted_height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window)
  {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show()
{
  if (!window_handle_)
  {
    return false;
  }

  // In PiP mode (desktop mini window), avoid maximizing on first show.
  // Detect via environment variable set by the Dart side.
  bool pip_mode = false;
#if defined(_WIN32)
  wchar_t buf[8];
  DWORD len = GetEnvironmentVariableW(L"CB_PIP_MODE", buf, 8);
  if (len > 0 && buf[0] == L'1')
  {
    pip_mode = true;
  }
#endif

  return ShowWindow(window_handle_, pip_mode ? SW_SHOWNORMAL : SW_SHOWMAXIMIZED);
}

bool Win32Window::ShowMaximized()
{
  if (!window_handle_)
  {
    return false;
  }

  // Use the proper Windows maximize command and ensure it persists
  BOOL result = ShowWindow(window_handle_, SW_SHOWMAXIMIZED);

  // Force the window to redraw after maximizing
  UpdateWindow(window_handle_);

  return result;
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept
{
  if (message == WM_NCCREATE)
  {
    auto window_struct = reinterpret_cast<CREATESTRUCT *>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window *>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  }
  else if (Win32Window *that = GetThisFromHandle(window))
  {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept
{
  switch (message)
  {
  case WM_ERASEBKGND:
  {
    // Paint background black to avoid white flash before Flutter draws.
    HDC hdc = reinterpret_cast<HDC>(wparam);
    RECT rc;
    GetClientRect(hwnd, &rc);
    HBRUSH brush = reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    FillRect(hdc, &rc, brush);
    return 1; // Non-zero to indicate background erased.
  }

  case WM_DESTROY:
    window_handle_ = nullptr;
    Destroy();
    if (quit_on_close_)
    {
      PostQuitMessage(0);
    }
    return 0;

  case WM_DPICHANGED:
  {
    auto newRectSize = reinterpret_cast<RECT *>(lparam);
    LONG newWidth = newRectSize->right - newRectSize->left;
    LONG newHeight = newRectSize->bottom - newRectSize->top;

    SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                 newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

    return 0;
  }

  case WM_SIZE:
  {
    // When window size changes, make sure to reposition the child content correctly
    RECT rect = GetClientArea();
    if (child_content_ != nullptr)
    {
      // Size and position the child window.
      MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                 rect.bottom - rect.top, TRUE);
    }
    return 0;
  }

  case WM_GETMINMAXINFO:
  {
    // Ensure the window can be properly maximized to fill the entire screen
    LPMINMAXINFO lpMMI = (LPMINMAXINFO)lparam;

    // Get the monitor info for proper maximization
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (monitor != NULL)
    {
      MONITORINFO monitorInfo;
      monitorInfo.cbSize = sizeof(monitorInfo);
      if (GetMonitorInfo(monitor, &monitorInfo))
      {
        // Set the max tracking size to the monitor's work area
        lpMMI->ptMaxTrackSize.x = monitorInfo.rcWork.right - monitorInfo.rcWork.left;
        lpMMI->ptMaxTrackSize.y = monitorInfo.rcWork.bottom - monitorInfo.rcWork.top;

        // Set the maximized position and size
        lpMMI->ptMaxPosition.x = monitorInfo.rcWork.left - monitorInfo.rcMonitor.left;
        lpMMI->ptMaxPosition.y = monitorInfo.rcWork.top - monitorInfo.rcMonitor.top;
        lpMMI->ptMaxSize.x = monitorInfo.rcWork.right - monitorInfo.rcWork.left;
        lpMMI->ptMaxSize.y = monitorInfo.rcWork.bottom - monitorInfo.rcWork.top;
      }
    }
    return 0;
  }

  case WM_ACTIVATE:
    // Only set focus when the window is being activated (WA_ACTIVE or
    // WA_CLICKACTIVE).  Calling SetFocus during WA_INACTIVE (deactivation)
    // can cause the window to fight for foreground status and prevent the
    // Windows Shell from minimizing it via the taskbar button.
    if (child_content_ != nullptr && LOWORD(wparam) != WA_INACTIVE)
    {
      SetFocus(child_content_);
    }
    return 0;

  case WM_DWMCOLORIZATIONCOLORCHANGED:
    UpdateTheme(hwnd);
    return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy()
{
  OnDestroy();

  if (window_handle_)
  {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0)
  {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window *Win32Window::GetThisFromHandle(HWND const window) noexcept
{
  return reinterpret_cast<Win32Window *>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content)
{
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea()
{
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle()
{
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close)
{
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate()
{
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy()
{
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window)
{
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS)
  {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
