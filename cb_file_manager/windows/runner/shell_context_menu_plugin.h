#pragma once

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <optional>

class ShellContextMenuPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit ShellContextMenuPlugin(flutter::PluginRegistrarWindows* registrar);
  ~ShellContextMenuPlugin() override;

  ShellContextMenuPlugin(const ShellContextMenuPlugin&) = delete;
  ShellContextMenuPlugin& operator=(const ShellContextMenuPlugin&) = delete;

 private:
  class ShellMenuWorker;
  using MethodResultPtr =
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      MethodResultPtr result);
  std::optional<LRESULT> HandleWindowProc(HWND hwnd,
                                          UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam);
  // Runs `work` on the Shell menu worker thread and completes `result` with its
  // value back on the platform thread.
  void RunOnShellMenuWorker(
      MethodResultPtr result,
      std::function<flutter::EncodableValue(HWND worker_window)> work);

  flutter::PluginRegistrarWindows* registrar_;
  HWND top_level_window_ = nullptr;
  int window_proc_delegate_id_ = 0;
  std::unique_ptr<ShellMenuWorker> shell_menu_worker_;
  uint64_t next_request_id_ = 1;
  // Platform-thread only: flutter::MethodResult is not thread-safe.
  std::map<uint64_t, MethodResultPtr> pending_results_;
};
