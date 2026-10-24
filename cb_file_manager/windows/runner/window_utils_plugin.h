#ifndef RUNNER_WINDOW_UTILS_PLUGIN_H_
#define RUNNER_WINDOW_UTILS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <memory>
#include <string>

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
    void RemoveTorrentNotification();
    // Tab merging: this window's tab strip as a drop target for windows that
    // are being dragged by a tab (see RunTabWindowDrag).
    void PublishTabStripRect();
    void RemoveTabStripRect();
    bool ScreenToTabStripPoint(POINT screen_point, double *x, double *y) const;
    void UpdateTabMergeHover(POINT screen_point);
    void ClearTabMergeHover();
    bool HandleTabMergeMessage(HWND hwnd, UINT message, WPARAM wparam,
                               LPARAM lparam, LRESULT *result);
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue> &method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    flutter::PluginRegistrarWindows *registrar_;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
    HWND drop_target_hwnd_ = nullptr;
    IDropTarget *drop_target_ = nullptr;
    int window_proc_delegate_id_ = -1;
    HWND torrent_launch_hwnd_ = nullptr;
    HWND torrent_notification_hwnd_ = nullptr;
    // Per-instance backdrop state (avoids cross-window pollution via shared globals).
    bool backdrop_active_ = false;
    bool backdrop_prefer_acrylic_ = true;
    bool backdrop_dark_mode_ = false;
    // Tab strip in logical pixels relative to the Flutter view.
    bool has_tab_strip_ = false;
    double tab_strip_left_ = 0;
    double tab_strip_top_ = 0;
    double tab_strip_right_ = 0;
    double tab_strip_bottom_ = 0;
    HWND tab_strip_hwnd_ = nullptr;
    bool tab_merge_hovering_ = false;
    double tab_merge_hover_x_ = 0;
    double tab_merge_hover_y_ = 0;
    std::string tab_merge_label_;
};

#endif // RUNNER_WINDOW_UTILS_PLUGIN_H_
