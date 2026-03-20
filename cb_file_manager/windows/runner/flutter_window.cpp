#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "fc_native_video_thumbnail_plugin.h"
#include "app_icon_plugin.h"
#include "shell_context_menu_plugin.h"
#include "file_operations_plugin.h"
#include "window_utils_plugin.h"

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
    : project_(project) {}

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

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Window visibility is managed by Dart via the window_manager package.
  // This avoids startup flicker from multiple show/maximize transitions on
  // Windows when window options (e.g. hidden title bar) are applied.
  return true;
}

void FlutterWindow::OnDestroy()
{
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
