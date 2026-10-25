#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <window_manager/window_manager_plugin.h>
#include "fc_native_video_thumbnail_plugin.h"
#include "app_icon_plugin.h"
#include "app_insights_plugin.h"
#include "shell_context_menu_plugin.h"
#include "file_operations_plugin.h"
#include "window_utils_plugin.h"
#include "store_update_plugin.h"
#include "custom_frame_message.h"

namespace
{
  bool CenterTorrentOptionsOnParent(HWND window, HWND parent)
  {
    if (!::IsWindow(parent)) parent = nullptr;
    POINT cursor{};
    ::GetCursorPos(&cursor);
    const HMONITOR monitor = parent
        ? ::MonitorFromWindow(parent, MONITOR_DEFAULTTONEAREST)
        : ::MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!::GetMonitorInfo(monitor, &info)) return false;
    const RECT work = info.rcWork;
    RECT anchor = work;
    if (parent && !::IsIconic(parent)) ::GetWindowRect(parent, &anchor);

    const double target_dpi = FlutterDesktopGetDpiForMonitor(monitor);
    const UINT current_dpi = ::GetDpiForWindow(window);
    RECT current{};
    ::GetWindowRect(window, &current);
    const double scale = current_dpi > 0 ? target_dpi / current_dpi : 1.0;
    LONG width = static_cast<LONG>((current.right - current.left) * scale);
    LONG height = static_cast<LONG>((current.bottom - current.top) * scale);
    if (width <= 0 || height <= 0) return false;
    if (width > work.right - work.left) width = work.right - work.left;
    if (height > work.bottom - work.top) height = work.bottom - work.top;
    LONG left = (anchor.left + anchor.right - width) / 2;
    LONG top = (anchor.top + anchor.bottom - height) / 2;
    if (left + width > work.right) left = work.right - width;
    if (top + height > work.bottom) top = work.bottom - height;
    if (left < work.left) left = work.left;
    if (top < work.top) top = work.top;

    const UINT flags = SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER;
    if (!::SetWindowPos(window, nullptr, left, top, width, height, flags))
      return false;
    // Crossing monitors can synchronously apply WM_DPICHANGED's suggested
    // rectangle. Finalize the intended physical bounds before exposing a frame.
    return ::SetWindowPos(window, nullptr, left, top, width, height, flags) != FALSE;
  }
}

FlutterWindow::FlutterWindow(const flutter::DartProject &project,
                             EngineWindowHost::Environment environment)
    : project_(project), environment_(std::move(environment)) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate()
{
  if (!Win32Window::OnCreate())
  {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view())
  {
    return false;
  }
  // Attach the rendering view before plugins cache GA_ROOT or register OLE
  // drop targets. Otherwise they retain the unparented child HWND and file
  // operation completion messages never reach the top-level window delegate.
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  mouse_input_guard_ = std::make_unique<FlutterMouseInputGuard>(
      flutter_controller_->view()->GetNativeWindow());
  EngineWindowHost::Register(this, flutter_controller_->engine(), environment_);
  wchar_t role[32];
  const DWORD role_length = GetEnvironmentVariableW(L"CB_WINDOW_ROLE", role, 32);
  const auto engine_role = environment_.find("CB_WINDOW_ROLE");
  if ((engine_role != environment_.end() && engine_role->second == "torrent-options") ||
      (engine_role == environment_.end() && role_length > 0 && role_length < 32 &&
       wcscmp(role, L"torrent-options") == 0))
  {
    // This form only needs window positioning/chrome. Avoid initializing video,
    // PDF, network, AI and shell integrations before its first frame. The folder
    // picker and preferences on Windows use Dart/FFI, not these native plugins.
    ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
        flutter_controller_->engine()->GetRegistrarForPlugin(
            "ScreenRetrieverWindowsPluginCApi"));
    WindowManagerPluginRegisterWithRegistrar(
        flutter_controller_->engine()->GetRegistrarForPlugin(
            "WindowManagerPlugin"));
    flutter::MethodChannel<flutter::EncodableValue> channel(
        flutter_controller_->engine()->messenger(),
        "cb_file_manager/torrent_options_window",
        &flutter::StandardMethodCodec::GetInstance());
    channel.SetMethodCallHandler(
        [window = GetHandle()](const auto &call, auto result) {
          if (call.method_name() != "centerOnParent")
          {
            result->NotImplemented();
            return;
          }
          HWND parent = nullptr;
          const auto *args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args)
          {
            const auto it = args->find(flutter::EncodableValue("parentWindowId"));
            if (it != args->end())
            {
              int64_t id = 0;
              if (const auto *value64 = std::get_if<int64_t>(&it->second)) id = *value64;
              else if (const auto *value32 = std::get_if<int32_t>(&it->second)) id = *value32;
              parent = reinterpret_cast<HWND>(static_cast<INT_PTR>(id));
            }
          }
          result->Success(flutter::EncodableValue(
              CenterTorrentOptionsOnParent(window, parent)));
        });
    return true;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Manually register FC Native Video Thumbnail plugin
  auto registrar = flutter_controller_->engine()->GetRegistrarForPlugin("FcNativeVideoThumbnailPlugin");
  fc_native_video_thumbnail::FcNativeVideoThumbnailPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));

  // Manually register App Icon plugin
  auto icon_registrar = flutter_controller_->engine()->GetRegistrarForPlugin("AppIconPlugin");
  AppIconPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(icon_registrar));

  // Manually register the read-only Windows app inventory plugin.
  auto app_insights_registrar =
      flutter_controller_->engine()->GetRegistrarForPlugin("AppInsightsPlugin");
  AppInsightsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(
              app_insights_registrar));

  // Manually register Shell Context Menu plugin
  auto shell_menu_registrar =
      flutter_controller_->engine()->GetRegistrarForPlugin("ShellContextMenuPlugin");
  ShellContextMenuPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(shell_menu_registrar));

  // Manually register File Operations plugin
  auto file_ops_registrar =
      flutter_controller_->engine()->GetRegistrarForPlugin("FileOperationsPlugin");
  file_operations_plugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(file_ops_registrar));

  // Manually register Window Utils plugin (runner-side utility channel)
  auto window_utils_registrar =
      flutter_controller_->engine()->GetRegistrarForPlugin("WindowUtilsPlugin");
  WindowUtilsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(window_utils_registrar));

  // Manually register Microsoft Store update plugin (MSIX builds only).
  auto store_update_registrar =
      flutter_controller_->engine()->GetRegistrarForPlugin("StoreUpdatePlugin");
  StoreUpdatePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(store_update_registrar));

  // After every plugin: media_kit_video swaps this window's WNDPROC.
  ReclaimWindowProc();

  // Window visibility is managed by Dart via the window_manager package.
  // This avoids startup flicker from multiple show/maximize transitions on
  // Windows when window options (e.g. hidden title bar) are applied.
  return true;
}

void FlutterWindow::OnDestroy()
{
  EngineWindowHost::OnDestroyed(this);
  mouse_input_guard_.reset();
  if (flutter_controller_)
  {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept
{
  return DispatchCustomFrameMessage(
      hwnd, message, wparam, lparam, [&](LPARAM forwarded_lparam) {
        return DispatchMessageToPlugins(hwnd, message, wparam, forwarded_lparam);
      });
}

LRESULT FlutterWindow::DispatchMessageToPlugins(HWND hwnd, UINT message,
                                               WPARAM wparam,
                                               LPARAM lparam) noexcept
{
  if (message == EngineWindowHost::kCloseWindowMessage) {
    EngineWindowHost::Close(this);
    return 0;
  }
  if (message == WM_CLOSE && EngineWindowHost::HandleClose(this)) return 0;
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_)
  {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result)
    {
      return *result;
    }
  }

  switch (message)
  {
  case WM_FONTCHANGE:
    flutter_controller_->engine()->ReloadSystemFonts();
    break;
  case WM_SYSCOMMAND:
  {
    // Block the Alt+Space system menu popup.  With TitleBarStyle.hidden the
    // native system menu is not useful (custom caption buttons are rendered
    // by Flutter).  We keep WS_SYSMENU in the window style because
    // WS_MINIMIZEBOX depends on it for taskbar click-to-minimize, but
    // suppress the menu itself here.
    const WORD cmd = wparam & 0xFFF0;
    if (cmd == SC_KEYMENU)
    {
      return 0;
    }
    break;
  }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
