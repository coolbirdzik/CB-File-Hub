#ifndef RUNNER_WINDOW_UTILS_PLUGIN_H_
#define RUNNER_WINDOW_UTILS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <memory>

struct IDropTarget;

class WindowUtilsPlugin : public flutter::Plugin
{
public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

    explicit WindowUtilsPlugin(flutter::PluginRegistrarWindows *registrar);
    virtual ~WindowUtilsPlugin();

    WindowUtilsPlugin(const WindowUtilsPlugin &) = delete;
    WindowUtilsPlugin &operator=(const WindowUtilsPlugin &) = delete;

private:
    void EnsureDropTargetRegistered();
    // Registers a Win32 message delegate that re-applies the DWM accent policy
    // whenever Windows resets it (WM_ACTIVATE, WM_NCACTIVATE, theme change, etc.)
    void EnsureWindowProcDelegateRegistered();
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue> &method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    flutter::PluginRegistrarWindows *registrar_;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
    HWND drop_target_hwnd_ = nullptr;
    IDropTarget *drop_target_ = nullptr;
    int window_proc_delegate_id_ = -1;
    // Per-instance backdrop state (avoids cross-window pollution via shared globals).
    bool backdrop_active_ = false;
    bool backdrop_prefer_acrylic_ = true;
    bool backdrop_dark_mode_ = false;
};

#endif // RUNNER_WINDOW_UTILS_PLUGIN_H_
