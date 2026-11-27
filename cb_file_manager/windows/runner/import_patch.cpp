#include "import_patch.h"

#include <cstring>

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
