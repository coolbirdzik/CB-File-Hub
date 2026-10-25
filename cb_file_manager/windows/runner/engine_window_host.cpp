#include "engine_window_host.h"

#include <flutter/dart_project.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <dwmapi.h>

#include <memory>
#include <vector>
#include <set>
#include <algorithm>
#include <cstdlib>

#include "flutter_window.h"
#include "utils.h"

namespace EngineWindowHost {
namespace {
struct Entry {
  FlutterWindow* window;
  std::string id;
  std::string role;
  bool closed = false;
  std::set<std::string> retain;
  flutter::BinaryMessenger* messenger = nullptr;
  // Retain reasons for finite work that must finish even after the last
  // visible window closes (file operations, model downloads).
  std::set<std::string> keep_process;
};
std::vector<Entry> entries;
std::vector<std::unique_ptr<FlutterWindow>> windows;
FlutterWindow* primary = nullptr;
bool enabled = false;
bool shutting_down = false;
bool quit_pending = false;
unsigned quit_round = 0;
UINT_PTR quit_timer = 0;
unsigned long next_id = 1;
// Engines that do not answer releaseMedia in time are torn down anyway.
constexpr UINT kReleaseMediaTimeoutMs = 4000;

Entry* Find(FlutterWindow* window) {
  for (auto& entry : entries) {
    if (entry.window == window) return &entry;
  }
  return nullptr;
}

bool KeepsAlive(const Entry& entry) {
  if (entry.role == "spare" || entry.role == "preparing" ||
      entry.role == "torrent-options") {
    return false;
  }
  return !entry.closed || !entry.keep_process.empty();
}

bool AnyKeepsAlive() {
  for (const auto& entry : entries) {
    if (KeepsAlive(entry)) return true;
  }
  return false;
}

void FinishQuit() {
  if (!quit_pending) return;
  quit_pending = false;
  if (quit_timer) {
    KillTimer(nullptr, quit_timer);
    quit_timer = 0;
  }
  // A window may have reopened while the engines released their media.
  if (!AnyKeepsAlive()) PostQuitMessage(0);
}

void CALLBACK OnReleaseMediaTimeout(HWND, UINT, UINT_PTR, DWORD) {
  FinishQuit();
}

void CheckLastWindow() {
  if (shutting_down || quit_pending || AnyKeepsAlive()) return;
  // Every engine is torn down once the message loop ends. Each releases its
  // media first: libmpv's thread calling back into a destroyed isolate aborts
  // the process ("Callback invoked after it has been deleted").
  auto remaining = std::make_shared<size_t>(0);
  for (const auto& entry : entries) {
    if (entry.messenger) ++*remaining;
  }
  if (*remaining == 0) {
    PostQuitMessage(0);
    return;
  }
  quit_pending = true;
  const unsigned round = ++quit_round;
  quit_timer = SetTimer(nullptr, 0, kReleaseMediaTimeoutMs, OnReleaseMediaTimeout);
  // Late answers from a timed-out round must not end a newer one.
  const auto released = [remaining, round] {
    if (--*remaining == 0 && round == quit_round) FinishQuit();
  };
  for (const auto& entry : entries) {
    if (!entry.messenger) continue;
    flutter::MethodChannel<flutter::EncodableValue> channel(
        entry.messenger, "cb_file_manager/engine_windows",
        &flutter::StandardMethodCodec::GetInstance());
    channel.InvokeMethod(
        "releaseMedia", nullptr,
        std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
            [released](const flutter::EncodableValue*) { released(); },
            [released](const std::string&, const std::string&,
                       const flutter::EncodableValue*) { released(); },
            [released] { released(); }));
  }
}

std::string Value(const Environment& env, const std::string& key,
                  const std::string& fallback = "") {
  auto it = env.find(key);
  return it == env.end() ? fallback : it->second;
}

bool Create(const Environment& env) {
  // Reclaim closed shells only between channel callbacks, after their engine
  // and native window have already been destroyed.
  windows.erase(std::remove_if(windows.begin(), windows.end(), [](const auto& w) {
    if (w->GetHandle()) return false;
    entries.erase(std::remove_if(entries.begin(), entries.end(), [&](const Entry& e) {
      return e.window == w.get();
    }), entries.end());
    return true;
  }), windows.end());
  flutter::DartProject project(L"data");
  project.set_ui_thread_policy(PreferredUIThreadPolicy());
  project.set_impeller_switch(PreferredImpellerSwitch());
  const auto role = Value(env, "CB_WINDOW_ROLE", "normal");
  if (role == "video" || role == "torrent-options" || role == "progress") {
    project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
  }
  auto window = std::make_unique<FlutterWindow>(project, env);
  window->SetProgressWindow(role == "progress");
  Win32Window::Size size(1200, 800);
  if (role == "torrent-options") size = Win32Window::Size(720, 420);
  if (role == "progress") size = Win32Window::Size(420, 88);
  if (Value(env, "CB_PIP_MODE") == "1") size = Win32Window::Size(384, 216);
  bool created = false;
  if (role == "video" && Value(env, "CB_PIP_MODE") != "1") {
    const auto parent_value = Value(env, "CB_VIDEO_WINDOW_PARENT_HWND");
    HWND parent = reinterpret_cast<HWND>(static_cast<uintptr_t>(
        std::strtoull(parent_value.c_str(), nullptr, 10)));
    POINT cursor{};
    GetCursorPos(&cursor);
    const HMONITOR monitor = IsWindow(parent)
        ? MonitorFromWindow(parent, MONITOR_DEFAULTTONEAREST)
        : MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (GetMonitorInfo(monitor, &info)) {
      const RECT& work = info.rcWork;
      RECT anchor = work;
      if (IsWindow(parent) && !IsIconic(parent)) GetWindowRect(parent, &anchor);
      const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
      const LONG width = std::min(static_cast<LONG>(1200 * scale), work.right - work.left);
      const LONG height = std::min(static_cast<LONG>(800 * scale), work.bottom - work.top);
      const LONG left = std::clamp((anchor.left + anchor.right - width) / 2, work.left, work.right - width);
      const LONG top = std::clamp((anchor.top + anchor.bottom - height) / 2, work.top, work.bottom - height);
      const RECT bounds{left, top, left + width, top + height};
      created = window->CreateWithPhysicalBounds(L"CB File Hub", bounds,
          Value(env, "CB_VIDEO_WINDOW_INITIALLY_MAXIMIZED") == "1");
    }
  } else {
    created = window->Create(L"CB File Hub", Win32Window::Point(0, 0), size);
  }
  if (!created) {
    return false;
  }
  window->SetQuitOnClose(false);
  windows.push_back(std::move(window));
  return true;
}
}  // namespace

void Register(FlutterWindow* window, flutter::FlutterEngine* engine,
              const Environment& environment) {
  if (!primary) primary = window;
  const bool is_primary = window == primary;
  const auto id = is_primary ? "primary" : std::to_string(next_id++);
  entries.push_back({window, id, Value(environment, "CB_WINDOW_ROLE", "normal"), false, {}, engine->messenger()});
  flutter::MethodChannel<flutter::EncodableValue> channel(
      engine->messenger(), "cb_file_manager/engine_windows",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [window, environment, is_primary, id](const auto& call, auto result) {
        using flutter::EncodableMap;
        using flutter::EncodableValue;
        if (call.method_name() == "startup") {
          enabled = true;
          primary->SetQuitOnClose(false);
          EncodableMap env;
          for (const auto& pair : environment) {
            env[EncodableValue(pair.first)] = EncodableValue(pair.second);
          }
          result->Success(EncodableValue(EncodableMap{
              {EncodableValue("primary"), EncodableValue(is_primary)},
              {EncodableValue("engineId"), EncodableValue(id)},
              {EncodableValue("environment"), EncodableValue(env)}}));
        } else if (call.method_name() == "create") {
          Environment env;
          const auto* args = std::get_if<EncodableMap>(call.arguments());
          if (!args) { result->Error("arguments", "Missing environment"); return; }
          auto it = args->find(EncodableValue("environment"));
          if (it == args->end() || !std::holds_alternative<EncodableMap>(it->second)) {
            result->Error("arguments", "Invalid environment"); return;
          }
          for (const auto& pair : std::get<EncodableMap>(it->second)) {
            const auto* key = std::get_if<std::string>(&pair.first);
            const auto* value = std::get_if<std::string>(&pair.second);
            if (key && value && key->rfind("CB_", 0) == 0) env[*key] = *value;
          }
          result->Success(EncodableValue(Create(env)));
        } else if (call.method_name() == "retain") {
          const auto* args = std::get_if<EncodableMap>(call.arguments());
          auto* entry = Find(window);
          if (args && entry) {
            const auto reason_it = args->find(EncodableValue("reason"));
            const auto busy_it = args->find(EncodableValue("busy"));
            const auto keep_it = args->find(EncodableValue("keepsProcess"));
            if (reason_it != args->end() && busy_it != args->end()) {
              const auto* reason = std::get_if<std::string>(&reason_it->second);
              const auto* busy = std::get_if<bool>(&busy_it->second);
              const bool* keeps = keep_it == args->end()
                  ? nullptr
                  : std::get_if<bool>(&keep_it->second);
              if (reason && busy) {
                if (*busy) {
                  entry->retain.insert(*reason);
                  if (!keeps || *keeps) entry->keep_process.insert(*reason);
                } else {
                  entry->retain.erase(*reason);
                  entry->keep_process.erase(*reason);
                }
                if (entry->closed) {
                  if (entry->retain.empty() && window != primary) {
                    PostMessage(window->GetHandle(), kCloseWindowMessage, 0, 0);
                  } else {
                    // Finished work may have been all that kept the process.
                    CheckLastWindow();
                  }
                }
              }
            }
          }
          result->Success();
        } else if (call.method_name() == "close") {
          result->Success();
          // Leave the channel callback before destroying its engine.
          PostMessage(window->GetHandle(), kCloseWindowMessage, 0, 0);
        } else if (call.method_name() == "setRole") {
          const auto* role = std::get_if<std::string>(call.arguments());
          if (role) {
            if (auto* entry = Find(window)) {
              if (*role == "normal" &&
                  (entry->closed || entry->role == "background")) {
                // A primary/retained engine may have merged while cloaked.
                // Reopening it must release that native drag state too.
                const HWND hwnd = window->GetHandle();
                RemovePropW(hwnd, L"CBFileHub.Merged");
                RemovePropW(hwnd, L"CBFileHub.RevealHold");
                const BOOL cloaked = FALSE;
                DwmSetWindowAttribute(hwnd, 13, &cloaked, sizeof(cloaked));
              }
              entry->role = *role;
              entry->closed = false;
            }
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

bool HandleClose(FlutterWindow* window) {
  if (!enabled || shutting_down) return false;
  auto* entry = Find(window);
  // This dialog uses window_manager's preventClose to cancel/hide its form.
  if (!entry || !entry->messenger || entry->role == "torrent-options") return false;
  flutter::MethodChannel<flutter::EncodableValue> channel(
      entry->messenger, "cb_file_manager/engine_windows",
      &flutter::StandardMethodCodec::GetInstance());
  channel.InvokeMethod("closeRequested", nullptr);
  return true;
}

void Close(FlutterWindow* window) {
  if (auto* entry = Find(window)) entry->closed = true;
  if (window == primary || (Find(window) && !Find(window)->retain.empty())) {
    ShowWindow(window->GetHandle(), SW_HIDE);
    CheckLastWindow();
    return;
  }
  window->Destroy();
}

void OnDestroyed(FlutterWindow* window) {
  if (auto* entry = Find(window)) {
    entry->closed = true;
    entry->messenger = nullptr;
    // A destroyed engine's work died with it.
    entry->retain.clear();
    entry->keep_process.clear();
    if (enabled) CheckLastWindow();
  }
}

void RevealPrepared(HWND window) {
  // Promote before acknowledging the native reveal. The source may close its
  // last tab before the destination isolate processes onTabWindowRevealed.
  for (auto& entry : entries) {
    if (entry.window->GetHandle() == window && entry.role == "preparing") {
      entry.role = "normal";
      entry.closed = false;
      return;
    }
  }
}

void Shutdown() {
  shutting_down = true;
  windows.clear();
  entries.clear();
}
}  // namespace EngineWindowHost
