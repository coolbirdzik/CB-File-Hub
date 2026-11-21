#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <cwchar>
#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

flutter::UIThreadPolicy PreferredUIThreadPolicy() {
  const auto has_flag = [](const wchar_t* name) {
    wchar_t flag[2] = {};
    return ::GetEnvironmentVariableW(name, flag, ARRAYSIZE(flag)) == 1 &&
           flag[0] == L'1';
  };
  wchar_t role[32] = {};
  const DWORD role_length =
      ::GetEnvironmentVariableW(L"CB_WINDOW_ROLE", role, ARRAYSIZE(role));
  const bool tab_window = role_length == 0 ||
                          (role_length < ARRAYSIZE(role) &&
                           std::wcscmp(role, L"normal") == 0);
  if (tab_window && !has_flag(L"CB_START_HIDDEN") &&
      !has_flag(L"CB_START_DRAGGING") && !has_flag(L"CB_PIP_MODE") &&
      !has_flag(L"CB_VIDEO_WINDOW")) {
    wchar_t count[32] = {};
    const DWORD length =
        ::GetEnvironmentVariableW(L"CB_SHARED_ENGINE_WINDOWS", count,
                                  ARRAYSIZE(count));
    wchar_t* end = count;
    const long value =
        length < ARRAYSIZE(count) ? std::wcstol(count, &end, 10) : 0;
    if (end == count || *end != L'\0' || value > 0) {
      return flutter::UIThreadPolicy::RunOnPlatformThread;
    }
  }
  return has_flag(L"CB_MERGED_UI_THREAD")
             ? flutter::UIThreadPolicy::RunOnPlatformThread
             : flutter::UIThreadPolicy::RunOnSeparateThread;
}

flutter::ImpellerSwitch PreferredImpellerSwitch() {
  wchar_t value[16] = {};
  const DWORD length =
      ::GetEnvironmentVariableW(L"CB_WINDOWS_RENDERER", value, 16);
  if (length > 0 && length < 16) {
    if (wcscmp(value, L"skia") == 0) {
      return flutter::ImpellerSwitch::Disabled;
    }
    if (wcscmp(value, L"impeller") == 0) {
      return flutter::ImpellerSwitch::Enabled;
    }
  }
  // Impeller for every window. Scrolling a folder of video thumbnails in a
  // release build: without InstallD3D11ThreadingGuard both renderers crashed
  // in the NVIDIA driver; with it, Skia repeatedly lost its EGL context
  // ("Context Lost", the window stops drawing) while Impeller ran clean.
  // Enabled (not Default) keeps this independent of the engine's per-version
  // default; CB_WINDOWS_RENDERER=skia remains for comparisons.
  return flutter::ImpellerSwitch::Enabled;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
