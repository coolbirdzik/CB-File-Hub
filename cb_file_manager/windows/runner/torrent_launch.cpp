#include "torrent_launch.h"

#include <algorithm>
#include <cstring>
#include <cwchar>

namespace {
constexpr size_t kMaxSourceBytes = 32768 * 4;
constexpr size_t kMaxSources = 100;

bool IsSource(const std::string& source) {
  if (source.empty() || source.size() > kMaxSourceBytes ||
      source.find_first_of("\"\r\n") != std::string::npos) {
    return false;
  }
  for (unsigned char value : source) {
    if (value < 0x20) return false;
  }
  // Reject malformed UTF-8 before passing it to Flutter's standard codec.
  const int code_units = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, source.data(),
      static_cast<int>(source.size()), nullptr, 0);
  if (!code_units || code_units > 32768) {
    return false;
  }
  if (_strnicmp(source.c_str(), "magnet:", 7) == 0) return true;
  const auto separator = source.find_last_of("/\\:");
  const auto basename_start = separator == std::string::npos ? 0 : separator + 1;
  return source.front() != '-' && source.size() - basename_start > 8 &&
         _stricmp(source.c_str() + source.size() - 8, ".torrent") == 0;
}

struct Candidate {
  HWND hwnd;
  ULONG_PTR priority;
};

BOOL CALLBACK CollectShells(HWND hwnd, LPARAM context) {
  const auto priority = reinterpret_cast<ULONG_PTR>(
      GetPropW(hwnd, kTorrentLaunchPriority));
  if (priority < 1 || priority > 3) return TRUE;
  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (!process_id || process_id == GetCurrentProcessId()) return TRUE;

  // Do not hand off to a different installed/dev copy of the application.
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) return TRUE;
  wchar_t other_path[32768];
  DWORD length = 32768;
  const bool resolved = QueryFullProcessImageNameW(process, 0, other_path, &length) != FALSE;
  CloseHandle(process);
  wchar_t own_path[32768];
  if (!resolved || !GetModuleFileNameW(nullptr, own_path, 32768) ||
      _wcsicmp(own_path, other_path) != 0) return TRUE;

  reinterpret_cast<std::vector<Candidate>*>(context)->push_back({hwnd, priority});
  return TRUE;
}
}  // namespace

bool ReadTorrentLaunchMessage(const COPYDATASTRUCT* data,
                             std::vector<std::string>* sources) {
  if (!data || data->dwData != kTorrentLaunchMessage || !data->lpData ||
      !data->cbData || data->cbData > (kMaxSourceBytes + 1) * kMaxSources) {
    return false;
  }
  std::vector<std::string> parsed;
  const char* cursor = static_cast<const char*>(data->lpData);
  size_t remaining = data->cbData;
  while (remaining) {
    const char* end = static_cast<const char*>(memchr(cursor, 0, remaining));
    if (!end || parsed.size() >= kMaxSources) return false;
    std::string source(cursor, end);
    if (!IsSource(source)) return false;
    parsed.push_back(std::move(source));
    const size_t consumed = end - cursor + 1;
    cursor += consumed;
    remaining -= consumed;
  }
  *sources = std::move(parsed);
  return true;
}

bool TryForwardTorrentLaunch(const std::vector<std::string>& arguments) {
  std::string payload;
  size_t count = 0;
  for (const auto& argument : arguments) {
    if (argument == "--open-torrent") continue;
    // Mixed ordinary launches retain the existing Dart startup behavior.
    if (!IsSource(argument) || ++count > kMaxSources) return false;
    payload.append(argument).push_back('\0');
  }
  if (!count) return false;
  std::vector<Candidate> candidates;
  EnumWindows(CollectShells, reinterpret_cast<LPARAM>(&candidates));
  std::stable_sort(candidates.begin(), candidates.end(),
                   [](const Candidate& a, const Candidate& b) {
                     return a.priority > b.priority;
                   });
  COPYDATASTRUCT data{kTorrentLaunchMessage,
                      static_cast<DWORD>(payload.size()), payload.data()};
  for (const auto& candidate : candidates) {
    DWORD process_id = 0;
    GetWindowThreadProcessId(candidate.hwnd, &process_id);
    AllowSetForegroundWindow(process_id);
    DWORD_PTR accepted = 0;
    // Receiving only copies/enqueues the request; no IO or dialog is awaited.
    // Ignore a hung shell quickly so the normal startup fallback still works.
    if (SendMessageTimeoutW(candidate.hwnd, WM_COPYDATA, 0,
                            reinterpret_cast<LPARAM>(&data),
                            SMTO_ABORTIFHUNG | SMTO_BLOCK, 250, &accepted) && accepted) {
      return true;
    }
  }
  return false;
}
