// Standalone native unit test: no Flutter engine or real torrent data.
#include "../torrent_launch.h"

#include <iostream>
#include <stdexcept>

namespace {
const std::string kMagnet = "magnet:?xt=urn:btih:1111111111111111111111111111111111111111";
HWND received_by = nullptr;
int deliveries = 0;

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

LRESULT CALLBACK Receiver(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_COPYDATA) {
    std::vector<std::string> sources;
    if (!ReadTorrentLaunchMessage(reinterpret_cast<COPYDATASTRUCT*>(lp), &sources)) return FALSE;
    Check(sources == std::vector<std::string>{kMagnet}, "Incorrect forwarded sources");
    received_by = hwnd;
    ++deliveries;
    return TRUE;
  }
  return DefWindowProcW(hwnd, message, wp, lp);
}

void LaunchChild(bool expected) {
  wchar_t path[32768];
  GetModuleFileNameW(nullptr, path, 32768);
  std::wstring command = L"\"" + std::wstring(path) + L"\" --child";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  Check(CreateProcessW(path, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                       nullptr, nullptr, &startup, &process), "Child failed to start");
  const auto deadline = GetTickCount64() + 10000;
  while (WaitForSingleObject(process.hProcess, 5) == WAIT_TIMEOUT && GetTickCount64() < deadline) {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  }
  DWORD code = STILL_ACTIVE;
  GetExitCodeProcess(process.hProcess, &code);
  if (code == STILL_ACTIVE) TerminateProcess(process.hProcess, 3);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  Check(code == (expected ? 0u : 2u), "Unexpected native handoff result");
}
}  // namespace

int main(int argc, char**) {
  if (argc > 1) return TryForwardTorrentLaunch({kMagnet}) ? 0 : 2;
  try {
    std::vector<std::string> sources;
    std::string payload = kMagnet;
    payload.push_back(0);
    payload.append(u8"C:\\Downloads\\Tiếng Việt.torrent").push_back(0);
    COPYDATASTRUCT data{kTorrentLaunchMessage, static_cast<DWORD>(payload.size()), payload.data()};
    Check(ReadTorrentLaunchMessage(&data, &sources) && sources.size() == 2,
          "Unicode/multiple source payload rejected");
    --data.cbData;
    Check(!ReadTorrentLaunchMessage(&data, &sources), "Unterminated payload accepted");
    ++data.cbData;
    data.dwData = 0;
    Check(!ReadTorrentLaunchMessage(&data, &sources), "Unknown protocol accepted");
    data.dwData = kTorrentLaunchMessage;
    char invalid[] = "--unsafe.torrent";
    data.lpData = invalid;
    data.cbData = sizeof(invalid);
    Check(!ReadTorrentLaunchMessage(&data, &sources), "Invalid source accepted");
    char invalid_utf8[] = {'m', 'a', 'g', 'n', 'e', 't', ':', static_cast<char>(0xff), 0};
    data.lpData = invalid_utf8;
    data.cbData = sizeof(invalid_utf8);
    Check(!ReadTorrentLaunchMessage(&data, &sources), "Invalid UTF-8 accepted");
    Check(!TryForwardTorrentLaunch({"--open-torrent"}), "Empty request accepted");
    Check(!TryForwardTorrentLaunch({"C:\\.torrent"}), "Dotfile treated as torrent extension");
    Check(!TryForwardTorrentLaunch({kMagnet, "ordinary.txt"}), "Mixed launch swallowed");

    WNDCLASSW window_class{};
    window_class.lpfnWndProc = Receiver;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpszClassName = L"CBTorrentLaunchUnitTest";
    Check(RegisterClassW(&window_class) != 0, "Window class failed");
    const auto create = [&]() {
      return CreateWindowW(window_class.lpszClassName, L"Unit", WS_POPUP,
                           0, 0, 0, 0, nullptr, nullptr, window_class.hInstance, nullptr);
    };
    HWND primary = create();
    HWND engine = create();
    HWND spare = create();
    Check(primary && engine && spare, "Test windows failed");
    SetPropW(primary, kTorrentLaunchPriority, reinterpret_cast<HANDLE>(2));
    SetPropW(engine, kTorrentLaunchPriority, reinterpret_cast<HANDLE>(3));
    LaunchChild(true);
    Check(received_by == engine && deliveries == 1, "Engine owner not preferred / duplicate delivery");
    RemovePropW(engine, kTorrentLaunchPriority);
    LaunchChild(true);
    Check(received_by == primary && deliveries == 2, "Primary shell not preferred");
    RemovePropW(primary, kTorrentLaunchPriority);
    LaunchChild(false);
    Check(deliveries == 2, "Unready/spare window received launch");
    DestroyWindow(primary);
    DestroyWindow(engine);
    DestroyWindow(spare);
    std::cout << "Native torrent launch unit tests passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
