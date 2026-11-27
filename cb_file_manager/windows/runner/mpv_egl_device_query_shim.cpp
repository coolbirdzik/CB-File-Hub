#include "mpv_egl_device_query_shim.h"

#include <windows.h>

#include <atomic>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include "import_patch.h"

namespace {

// EGLDisplay is a pointer and EGLint a 32-bit int; libEGL.dll uses the
// default x64 calling convention.
using QueryStringFn = const char *(*)(void *display, int name);
using GetProcAddressFn = FARPROC(WINAPI *)(HMODULE, LPCSTR);

constexpr int kEglExtensions = 0x3055;
constexpr char kDeviceQuery[] = "EGL_EXT_device_query";

GetProcAddressFn g_get_proc_address = nullptr;
std::atomic<QueryStringFn> g_query_string{nullptr};

bool HasExtension(const char *list, const char *name) {
  const size_t length = std::strlen(name);
  for (const char *at = std::strstr(list, name); at;
       at = std::strstr(at + 1, name)) {
    const bool starts = at == list || at[-1] == ' ';
    const bool ends = at[length] == '\0' || at[length] == ' ';
    if (starts && ends) return true;
  }
  return false;
}

const char *QueryStringWithDeviceQuery(void *display, int name) {
  const QueryStringFn query = g_query_string.load();
  if (!query) return nullptr;
  const char *value = query(display, name);
  if (!display || name != kEglExtensions || !value ||
      HasExtension(value, kDeviceQuery)) {
    return value;
  }
  // Only claim what this ANGLE actually provides to clients.
  const char *client = query(nullptr, kEglExtensions);
  if (!client || !HasExtension(client, kDeviceQuery)) return value;

  // eglQueryString results must stay valid for the display's lifetime. A
  // display's list never changes, so one extended copy per string is kept.
  static std::mutex mutex;
  static std::unordered_map<const char *, std::unique_ptr<std::string>> cache;
  std::lock_guard<std::mutex> lock(mutex);
  auto &extended = cache[value];
  if (!extended) {
    extended = std::make_unique<std::string>(value);
    if (!extended->empty()) extended->push_back(' ');
    extended->append(kDeviceQuery);
  }
  return extended->c_str();
}

FARPROC WINAPI GetProcAddressHook(HMODULE module, LPCSTR name) {
  FARPROC proc = g_get_proc_address(module, name);
  // Ordinal lookups pass a value below 0x10000 instead of a string.
  if (!proc || reinterpret_cast<ULONG_PTR>(name) <= 0xFFFF ||
      std::strcmp(name, "eglQueryString") != 0) {
    return proc;
  }
  QueryStringFn expected = nullptr;
  g_query_string.compare_exchange_strong(
      expected, reinterpret_cast<QueryStringFn>(proc));
  if (g_query_string.load() != reinterpret_cast<QueryStringFn>(proc)) {
    return proc;  // Some other libEGL.dll; leave it alone.
  }
  static std::atomic<bool> logged{false};
  if (!logged.exchange(true)) {
    std::fprintf(stderr,
                 "MpvEglDeviceQueryShim: D3D11-EGL zero-copy interop enabled\n");
  }
  return reinterpret_cast<FARPROC>(&QueryStringWithDeviceQuery);
}

}  // namespace

void InstallMpvEglDeviceQueryShim() {
  static bool installed = false;
  if (installed) return;
  installed = true;
  wchar_t value[4] = {};
  if (::GetEnvironmentVariableW(L"CB_MPV_EGL_SHIM", value, 4) == 1 &&
      value[0] == L'0') {
    return;
  }
  // media_kit_video_plugin.dll delay-loads libmpv, so it is not mapped yet.
  // Load it from the executable's folder now; the later delay-load and
  // media_kit's FFI open then resolve to this same, already patched module.
  HMODULE mpv = ::GetModuleHandleW(L"libmpv-2.dll");
  if (!mpv) {
    wchar_t path[MAX_PATH];
    const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return;
    wchar_t *slash = std::wcsrchr(path, L'\\');
    if (!slash) return;
    const size_t room = MAX_PATH - static_cast<size_t>(slash + 1 - path);
    if (wcscpy_s(slash + 1, room, L"libmpv-2.dll") != 0) return;
    mpv = ::LoadLibraryExW(path, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!mpv) return;
  }
  PatchImport(mpv, "KERNEL32.dll", "GetProcAddress",
              reinterpret_cast<void *>(&GetProcAddressHook),
              reinterpret_cast<void **>(&g_get_proc_address));
}
