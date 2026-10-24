#ifndef RUNNER_ENGINE_WINDOW_HOST_H_
#define RUNNER_ENGINE_WINDOW_HOST_H_

#include <flutter/encodable_value.h>
#include <windows.h>
#include <flutter/flutter_engine.h>
#include <map>
#include <string>

class FlutterWindow;

// Owns secondary Flutter engines without using Flutter's internal window API.
namespace EngineWindowHost {
constexpr UINT kCloseWindowMessage = WM_APP + 0x60;
using Environment = std::map<std::string, std::string>;
void Register(FlutterWindow* window, flutter::FlutterEngine* engine,
              const Environment& environment);
bool HandleClose(FlutterWindow* window);
void Close(FlutterWindow* window);
void OnDestroyed(FlutterWindow* window);
void RevealPrepared(HWND window);
void Shutdown();
}

#endif
