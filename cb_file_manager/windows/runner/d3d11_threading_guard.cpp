#include "d3d11_threading_guard.h"

#include <windows.h>
#include <d3d11.h>

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

// Replaces |function| imported from |dll| in |module|'s import table.
bool PatchImport(HMODULE module, const char *dll, const char *function,
                 void *replacement, void **original) {
  auto *base = reinterpret_cast<BYTE *>(module);
  auto *dos = reinterpret_cast<IMAGE_DOS_HEADER *>(base);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE) return false;
  auto *nt = reinterpret_cast<IMAGE_NT_HEADERS *>(base + dos->e_lfanew);
  const IMAGE_DATA_DIRECTORY &dir =
      nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (!dir.VirtualAddress) return false;
  auto *desc =
      reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR *>(base + dir.VirtualAddress);
  for (; desc->Name; ++desc) {
    if (_stricmp(reinterpret_cast<const char *>(base + desc->Name), dll) != 0)
      continue;
    if (!desc->OriginalFirstThunk) continue;
    auto *names =
        reinterpret_cast<IMAGE_THUNK_DATA *>(base + desc->OriginalFirstThunk);
    auto *slots = reinterpret_cast<IMAGE_THUNK_DATA *>(base + desc->FirstThunk);
    for (; names->u1.AddressOfData; ++names, ++slots) {
      if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
      auto *by_name = reinterpret_cast<IMAGE_IMPORT_BY_NAME *>(
          base + names->u1.AddressOfData);
      if (std::strcmp(reinterpret_cast<const char *>(by_name->Name),
                      function) != 0) {
        continue;
      }
      DWORD old_protect = 0;
      if (!::VirtualProtect(&slots->u1.Function, sizeof(slots->u1.Function),
                            PAGE_READWRITE, &old_protect)) {
        return false;
      }
      *original = reinterpret_cast<void *>(slots->u1.Function);
      slots->u1.Function = reinterpret_cast<ULONG_PTR>(replacement);
      ::VirtualProtect(&slots->u1.Function, sizeof(slots->u1.Function),
                       old_protect, &old_protect);
      return true;
    }
  }
  return false;
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
