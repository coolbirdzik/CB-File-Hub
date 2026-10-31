#ifndef RUNNER_WINDOW_BACKDROP_DIAGNOSTICS_H_
#define RUNNER_WINDOW_BACKDROP_DIAGNOSTICS_H_

#include <cstdio>
#include <iterator>
#include "window_backdrop.h"
#include "window_backdrop_frame.h"

namespace WindowBackdrop {
// Opt-in native state only: no folder names, tab titles or preference contents.
inline void Trace(const char* event, HWND root, HWND view,
                  const State* state = nullptr) {
  wchar_t path[32768];
  const DWORD length = ::GetEnvironmentVariableW(
      L"CB_BACKDROP_TRACE_FILE", path, static_cast<DWORD>(std::size(path)));
  if (!length || length >= std::size(path)) return;
  const HANDLE file = ::CreateFileW(path, FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD material = 0;
  BOOL root_alpha = FALSE, child_alpha = FALSE;
  const HRESULT material_hr = ::DwmGetWindowAttribute(root,
      static_cast<DWMWINDOWATTRIBUTE>(38), &material, sizeof(material));
  const HRESULT root_hr = ::DwmGetWindowAttribute(root,
      static_cast<DWMWINDOWATTRIBUTE>(39), &root_alpha, sizeof(root_alpha));
  const HRESULT child_hr = view ? ::DwmGetWindowAttribute(view,
      static_cast<DWMWINDOWATTRIBUTE>(39), &child_alpha, sizeof(child_alpha)) : E_HANDLE;
  ACCENT_POLICY root_accent{};
  WINDOWCOMPOSITIONATTRIBDATA data{WCA_ACCENT_POLICY, &root_accent, sizeof(root_accent)};
  using GetComposition = BOOL(WINAPI*)(HWND, WINDOWCOMPOSITIONATTRIBDATA*);
  const auto get_composition = reinterpret_cast<GetComposition>(::GetProcAddress(
      ::GetModuleHandleW(L"user32.dll"), "GetWindowCompositionAttribute"));
  const int root_accent_state = get_composition && get_composition(root, &data)
      ? static_cast<int>(root_accent.AccentState) : -1;
  char line[1024];
  const int count = std::snprintf(line, sizeof(line),
      "%llu pid=%lu %s root=%p view=%p visible=%d max=%d iconic=%d pending=%d "
      "foreground=%d active=%d root_exstyle=%llx view_exstyle=%llx "
      "material=%lu/hr=%08lx root_accent=%d alpha=%d/%08lx child_alpha=%d/%08lx "
      "applied=%d enabled=%d lost=%d child_lost=%d child_unsupported=%d accent_acrylic=%d\n",
      ::GetTickCount64(), ::GetCurrentProcessId(), event, root, view,
      ::IsWindowVisible(root), ::IsZoomed(root), ::IsIconic(root),
      IsResizeFramePending(root),
      ::GetForegroundWindow() == root, ::GetActiveWindow() == root,
      static_cast<unsigned long long>(::GetWindowLongPtrW(root, GWL_EXSTYLE)),
      static_cast<unsigned long long>(::GetWindowLongPtrW(view, GWL_EXSTYLE)),
      material, static_cast<DWORD>(material_hr), root_accent_state,
      root_alpha, static_cast<DWORD>(root_hr),
      child_alpha, static_cast<DWORD>(child_hr), state ? state->applied : -1,
      state ? state->enabled : -1, state ? state->material_lost : -1,
      state ? state->child_transparency_lost : -1,
      state ? state->child_transparency_unsupported : -1,
      state ? state->accent_acrylic : -1);
  if (count > 0 && static_cast<size_t>(count) < sizeof(line)) {
    DWORD written = 0;
    ::WriteFile(file, line, static_cast<DWORD>(count), &written, nullptr);
  }
  ::CloseHandle(file);
}
}  // namespace WindowBackdrop

#endif  // RUNNER_WINDOW_BACKDROP_DIAGNOSTICS_H_
