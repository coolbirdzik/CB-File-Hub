#include "d3d11_threading_guard.h"

#include <windows.h>
#include <d3d11.h>

#include "import_patch.h"

#include <atomic>
#include <cstdio>
#include <cstring>

namespace {

using CreateDeviceFn = HRESULT(WINAPI *)(IDXGIAdapter *, D3D_DRIVER_TYPE,
                                         HMODULE, UINT,
                                         const D3D_FEATURE_LEVEL *, UINT, UINT,
                                         ID3D11Device **, D3D_FEATURE_LEVEL *,
                                         ID3D11DeviceContext **);
using GetProcAddressFn = FARPROC(WINAPI *)(HMODULE, LPCSTR);

std::atomic<CreateDeviceFn> g_create_device{nullptr};
GetProcAddressFn g_get_proc_address = nullptr;

HRESULT WINAPI CreateDeviceWithoutDriverThreads(
    IDXGIAdapter *adapter, D3D_DRIVER_TYPE driver_type, HMODULE software,
    UINT flags, const D3D_FEATURE_LEVEL *feature_levels, UINT level_count,
    UINT sdk_version, ID3D11Device **device, D3D_FEATURE_LEVEL *level,
    ID3D11DeviceContext **context) {
  const CreateDeviceFn create = g_create_device.load();
  if (!create) return E_FAIL;
  static std::atomic<bool> logged{false};
  if (!logged.exchange(true)) {
    std::fprintf(stderr,
                 "D3D11ThreadingGuard: device created without driver "
                 "threading optimizations\n");
  }
  return create(adapter, driver_type, software,
                flags | D3D11_CREATE_DEVICE_PREVENT_INTERNAL_THREADING_OPTIMIZATIONS,
                feature_levels, level_count, sdk_version, device, level,
                context);
}

FARPROC WINAPI GetProcAddressHook(HMODULE module, LPCSTR name) {
  FARPROC proc = g_get_proc_address(module, name);
  // Ordinal lookups pass a value below 0x10000 instead of a string.
  if (!proc || reinterpret_cast<ULONG_PTR>(name) <= 0xFFFF ||
      std::strcmp(name, "D3D11CreateDevice") != 0) {
    return proc;
  }
  CreateDeviceFn expected = nullptr;
  g_create_device.compare_exchange_strong(
      expected, reinterpret_cast<CreateDeviceFn>(proc));
  if (g_create_device.load() != reinterpret_cast<CreateDeviceFn>(proc)) {
    return proc;  // Some other d3d11.dll; leave it alone.
  }
  return reinterpret_cast<FARPROC>(&CreateDeviceWithoutDriverThreads);
}

}  // namespace

void InstallD3D11ThreadingGuard() {
  static bool installed = false;
  if (installed) return;
  installed = true;
  wchar_t value[4] = {};
  if (::GetEnvironmentVariableW(L"CB_D3D11_DRIVER_THREADS", value, 4) == 1 &&
      value[0] == L'1') {
    return;
  }
  HMODULE flutter = ::GetModuleHandleW(L"flutter_windows.dll");
  if (!flutter) return;
  // PatchImport stores the original before it swaps the slot, so the hook
  // never runs without it.
  PatchImport(flutter, "KERNEL32.dll", "GetProcAddress",
              reinterpret_cast<void *>(&GetProcAddressHook),
              reinterpret_cast<void **>(&g_get_proc_address));
}
