#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "engine_window_host.h"
#include "flutter_mouse_input_guard.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         EngineWindowHost::Environment environment = {});
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  LRESULT DispatchMessageToPlugins(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;

  // The project to run.
  flutter::DartProject project_;
  EngineWindowHost::Environment environment_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<FlutterMouseInputGuard> mouse_input_guard_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
