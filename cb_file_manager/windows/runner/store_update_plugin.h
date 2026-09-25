#ifndef STORE_UPDATE_PLUGIN_H_
#define STORE_UPDATE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <atomic>
#include <memory>

// Microsoft Store in-app updates (Windows.Services.Store.StoreContext) for the
// MSIX build. Direct-download builds are updated from Dart instead.
class StoreUpdatePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  explicit StoreUpdatePlugin(flutter::PluginRegistrarWindows* registrar);
  ~StoreUpdatePlugin() override;

  StoreUpdatePlugin(const StoreUpdatePlugin&) = delete;
  StoreUpdatePlugin& operator=(const StoreUpdatePlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND OwnerWindow() const;

  flutter::PluginRegistrarWindows* registrar_;
  // StorePackageUpdateStatus.TotalDownloadProgress of the running request.
  std::atomic<double> progress_{0.0};
  std::atomic<bool> busy_{false};
};

#endif  // STORE_UPDATE_PLUGIN_H_
