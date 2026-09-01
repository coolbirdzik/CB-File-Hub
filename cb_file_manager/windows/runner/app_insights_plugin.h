#ifndef APP_INSIGHTS_PLUGIN_H_
#define APP_INSIGHTS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

class AppInsightsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  AppInsightsPlugin();
  ~AppInsightsPlugin() override;

  AppInsightsPlugin(const AppInsightsPlugin&) = delete;
  AppInsightsPlugin& operator=(const AppInsightsPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

#endif  // APP_INSIGHTS_PLUGIN_H_
