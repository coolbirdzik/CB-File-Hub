// Standalone Win32 regression test: no Flutter engine or application E2E.
#include "../priority_message_loop.h"

#include <iostream>
#include <stdexcept>
#include <vector>

namespace {
constexpr UINT kTaskWakeUp = WM_APP + 1;
constexpr UINT_PTR kScrollTimer = 7;

std::vector<UINT> g_dispatched;

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

LRESULT CALLBACK Receiver(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  if (message == kTaskWakeUp) {
    g_dispatched.push_back(message);
    // Like Flutter's task runner while Dart has work: keep one wake-up queued.
    if (g_dispatched.size() < 50) ::PostMessageW(hwnd, kTaskWakeUp, 0, 0);
    return 0;
  }
  if (message == WM_TIMER && wp == kScrollTimer) {
    g_dispatched.push_back(message);
    ::KillTimer(hwnd, kScrollTimer);
    ::PostQuitMessage(0);
    return 0;
  }
  return ::DefWindowProcW(hwnd, message, wp, lp);
}

HWND CreateReceiver() {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = Receiver;
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.lpszClassName = L"PriorityMessageLoopTest";
  ::RegisterClassW(&window_class);
  return ::CreateWindowExW(0, window_class.lpszClassName, L"", 0, 0, 0, 0, 0,
                           HWND_MESSAGE, nullptr, window_class.hInstance,
                           nullptr);
}

// A due timer must run even while posted task messages never stop arriving.
void TimerIsNotStarvedByPostedTasks(HWND hwnd) {
  g_dispatched.clear();
  Check(::SetTimer(hwnd, kScrollTimer, USER_TIMER_MINIMUM, nullptr) != 0,
        "SetTimer failed");
  ::Sleep(50);
  ::PostMessageW(hwnd, kTaskWakeUp, 0, 0);
  RunPriorityMessageLoop();
  Check(!g_dispatched.empty() && g_dispatched.front() == WM_TIMER,
        "due WM_TIMER was dispatched after posted task messages");
  MSG msg;
  while (::PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
  }
}

// Posted messages still run when no input or timer is waiting.
void PostedMessagesStillRun(HWND hwnd) {
  g_dispatched.clear();
  ::PostMessageW(hwnd, kTaskWakeUp, 0, 0);
  ::SetTimer(hwnd, kScrollTimer, 200, nullptr);
  RunPriorityMessageLoop();
  Check(g_dispatched.size() >= 50, "posted task messages were not dispatched");
  Check(g_dispatched.back() == WM_TIMER, "loop ended before WM_QUIT");
}
}  // namespace

int main() {
  try {
    const HWND hwnd = CreateReceiver();
    Check(hwnd != nullptr, "CreateWindowEx failed");
    TimerIsNotStarvedByPostedTasks(hwnd);
    PostedMessagesStillRun(hwnd);
    ::DestroyWindow(hwnd);
    std::cout << "priority_message_loop_test passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAILED: " << error.what() << "\n";
    return 1;
  }
}
