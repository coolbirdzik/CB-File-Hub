#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "fc_native_video_thumbnail_plugin.h"

// Function to get the primary monitor work area dimensions
// This ensures we respect the taskbar and title bar areas
void GetPrimaryMonitorWorkArea(int *width, int *height)
{
  HMONITOR primaryMonitor = MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitorInfo = {0};
  monitorInfo.cbSize = sizeof(MONITORINFO);

  if (GetMonitorInfo(primaryMonitor, &monitorInfo))
  {
    // Use work area (excludes taskbar) instead of full monitor area
    *width = monitorInfo.rcWork.right - monitorInfo.rcWork.left;
    *height = monitorInfo.rcWork.bottom - monitorInfo.rcWork.top;
  }
  else
  {
    // Fallback to system metrics for work area if GetMonitorInfo fails
    *width = GetSystemMetrics(SM_CXMAXIMIZED);
    *height = GetSystemMetrics(SM_CYMAXIMIZED);
  }
}

// Placement of the dedicated video player window (CB_WINDOW_ROLE=video), in
// physical pixels. It opens centred over the window that launched it
// (CB_VIDEO_WINDOW_PARENT_HWND) and inside that window's monitor, or on the
// monitor under the cursor when the launcher is unknown. Creating the window in
// place avoids moving it (and DPI-rescaling it) after it is already visible.
static bool ResolveVideoWindowPlacement(RECT *bounds, bool *maximized)
{
  wchar_t role[32];
  DWORD role_len = GetEnvironmentVariableW(L"CB_WINDOW_ROLE", role, 32);
  if (role_len == 0 || role_len >= 32 || wcscmp(role, L"video") != 0)
  {
    return false;
  }

  HWND parent = nullptr;
  wchar_t parent_buf[32];
  DWORD parent_len =
      GetEnvironmentVariableW(L"CB_VIDEO_WINDOW_PARENT_HWND", parent_buf, 32);
  if (parent_len > 0 && parent_len < 32)
  {
    parent = reinterpret_cast<HWND>(
        static_cast<INT_PTR>(_wcstoi64(parent_buf, nullptr, 10)));
    if (!IsWindow(parent))
    {
      parent = nullptr;
    }
  }

  HMONITOR monitor = nullptr;
  if (parent)
  {
    monitor = MonitorFromWindow(parent, MONITOR_DEFAULTTONEAREST);
  }
  else
  {
    POINT cursor{};
    GetCursorPos(&cursor);
    monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  }

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(monitor, &monitor_info))
  {
    return false;
  }
  const RECT &work = monitor_info.rcWork;

  // Centre over the launcher; over the work area when it is unknown or
  // minimized (a minimized window's rect is off-screen).
  RECT anchor = work;
  if (parent && !IsIconic(parent))
  {
    GetWindowRect(parent, &anchor);
  }

  // Same logical size as the other secondary windows, capped to the work area.
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  LONG width = static_cast<LONG>(1200 * scale);
  LONG height = static_cast<LONG>(800 * scale);
  if (width > work.right - work.left)
  {
    width = work.right - work.left;
  }
  if (height > work.bottom - work.top)
  {
    height = work.bottom - work.top;
  }

  LONG left = (anchor.left + anchor.right) / 2 - width / 2;
  LONG top = (anchor.top + anchor.bottom) / 2 - height / 2;
  if (left + width > work.right)
  {
    left = work.right - width;
  }
  if (top + height > work.bottom)
  {
    top = work.bottom - height;
  }
  if (left < work.left)
  {
    left = work.left;
  }
  if (top < work.top)
  {
    top = work.top;
  }
  *bounds = {left, top, left + width, top + height};

  wchar_t maximized_buf[8];
  DWORD maximized_len = GetEnvironmentVariableW(
      L"CB_VIDEO_WINDOW_INITIALLY_MAXIMIZED", maximized_buf, 8);
  *maximized = maximized_len > 0 && maximized_len < 8 && maximized_buf[0] == L'1';
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // A file manager touches every mounted letter, including empty card readers,
  // optical drives with no disc and mapped shares whose server is gone. By
  // default Windows answers those with a modal hard-error box and holds the
  // calling thread until it is dismissed, which shows up as the app hanging.
  // Ask for a plain error code instead. Set before any thread is created so
  // every thread the Dart VM spawns inherits it.
  ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // Detect PiP mode via environment variable set by Dart side
  bool pip_mode = false;
  wchar_t pipBuf[8];
  DWORD pipLen = GetEnvironmentVariableW(L"CB_PIP_MODE", pipBuf, 8);
  if (pipLen > 0 && pipBuf[0] == L'1')
  {
    pip_mode = true;
  }

  bool secondary_window = false;
  wchar_t secondaryBuf[8];
  DWORD secondaryLen =
      GetEnvironmentVariableW(L"CB_SECONDARY_WINDOW", secondaryBuf, 8);
  if (secondaryLen > 0 && secondaryBuf[0] == L'1')
  {
    secondary_window = true;
  }

  // Detect progress window role
  bool progress_mode = false;
  wchar_t roleBuf[32];
  DWORD roleLen = GetEnvironmentVariableW(L"CB_WINDOW_ROLE", roleBuf, 32);
  if (roleLen > 0 && wcscmp(roleBuf, L"progress") == 0)
  {
    progress_mode = true;
  }

  // Prepare origin and size
  Win32Window::Point origin(0, 0);
  Win32Window::Size size(0, 0);

  if (pip_mode)
  {
    // Small initial window for PiP; will be adjusted by window_manager later
    size = Win32Window::Size(384, 216);
  }
  else if (progress_mode)
  {
    // Progress window: exact final size, no resize needed.
    // Must match the Dart-side WindowOptions size to avoid flicker.
    size = Win32Window::Size(420, 88);
  }
  else if (secondary_window)
  {
    // Secondary windows should start with a browser-like size.
    // This avoids creating a full-screen-sized surface and then shrinking it.
    size = Win32Window::Size(1200, 800);
  }
  else
  {
    // Get work area dimensions (respects taskbar and title bar)
    int screenWidth = 0;
    int screenHeight = 0;
    GetPrimaryMonitorWorkArea(&screenWidth, &screenHeight);
    size = Win32Window::Size(screenWidth, screenHeight);
  }

  RECT video_bounds{};
  bool video_maximized = false;
  // A PiP window spawned from the player inherits its CB_WINDOW_ROLE=video.
  const bool created =
      !pip_mode && ResolveVideoWindowPlacement(&video_bounds, &video_maximized)
          ? window.CreateWithPhysicalBounds(L"CB File Hub", video_bounds,
                                            video_maximized)
          : window.Create(L"CB File Hub", origin, size);
  if (!created)
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
