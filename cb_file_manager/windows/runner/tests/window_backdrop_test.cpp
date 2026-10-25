// Native API regression tests, independent of Flutter and app E2E.
#include <windows.h>
#include <dwmapi.h>
#include <cstring>
#include <iostream>
#include <map>
#include <stdexcept>
#include <vector>

namespace {
bool material_ok = true, accent_ok = true;
int legacy_acrylic_calls = 0, legacy_blur_calls = 0;
std::map<HWND, BOOL> alpha;
std::vector<int> materials;
HRESULT WINAPI Attribute(HWND hwnd, DWORD id, LPCVOID value, DWORD) {
  if (id == 38) {
    const int material = *static_cast<const int*>(value);
    materials.push_back(material);
    if (material != 1 && !material_ok) return E_FAIL;
  }
  if (id == 1029 && !material_ok) return E_FAIL;
  if (id == 39) alpha[hwnd] = *static_cast<const BOOL*>(value);
  return S_OK;
}
BOOL WINAPI Accent(HWND, void* raw) {
  struct Composition { int attribute; void* data; SIZE_T size; };
  const int state = *static_cast<const int*>(static_cast<Composition*>(raw)->data);
  if (state == 4) ++legacy_acrylic_calls;
  if (state == 3) ++legacy_blur_calls;
  return state == 0 || accent_ok;
}
FARPROC WINAPI Lookup(HMODULE module, LPCSTR name) {
  if (std::strcmp(name, "SetWindowCompositionAttribute") == 0) {
    return reinterpret_cast<FARPROC>(&Accent);
  }
  return ::GetProcAddress(module, name);
}
void Check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}
}  // namespace

#define DwmSetWindowAttribute Attribute
#define GetProcAddress Lookup
#include "../window_backdrop.h"
#undef GetProcAddress
#undef DwmSetWindowAttribute

int main() {
  try {
    const HWND root = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        L"STATIC", L"Backdrop test", WS_OVERLAPPEDWINDOW,
        -32000, -32000, 400, 300, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    const HWND child = CreateWindowExW(0, L"STATIC", L"", WS_CHILD,
        0, 0, 400, 300, root, nullptr, GetModuleHandleW(nullptr), nullptr);
    Check(root && child, "Could not create native backdrop receivers");

    // A successful host-brush flag is NOT a successful material. Fall back.
    material_ok = false;
    Check(WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, false),
          "Legacy acrylic fallback failed");
    Check(legacy_acrylic_calls == 1,
          "Host-brush success incorrectly skipped the acrylic fallback");

    // A previous working material may disappear after minimize/restore.
    material_ok = true;
    Check(WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, true),
          "Could not initialize acrylic");
    Check(alpha[root] && alpha[child], "Working acrylic did not expose the material");
    for (int i = 0; i < 32; ++i) {
      materials.clear();
      Check(WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, i % 2),
            "Repeated material restore failed");
      Check(materials.size() >= 2 && materials[0] == 1 && materials.back() == 3,
            "Restore reused the cached material enum without rebuilding it");
    }

    material_ok = accent_ok = false;
    Check(!WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, false),
          "Missing material was incorrectly reported as successful");
    Check(!alpha[root] && !alpha[child],
          "Failed backdrop left a fully transparent root or Flutter view");

    // Dark mode success alone must not hide a failed early-Windows-11 Mica API.
    accent_ok = true;
    const int blur_before = legacy_blur_calls;
    Check(WindowBackdrop::ApplyToWindow(root, child, 22000, true, false, true),
          "Legacy blur fallback failed");
    Check(legacy_blur_calls == blur_before + 1,
          "Dark-mode success incorrectly skipped the material fallback");

    material_ok = true;
    Check(WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, false),
          "Backdrop did not recover after a transient API failure");
    Check(WindowBackdrop::ApplyToWindow(root, child, 26100, false, true, false),
          "Wallpaper mode could not disable the native backdrop");
    Check(!alpha[root] && !alpha[child] && materials.back() == 1,
          "Disabled backdrop retained alpha or a material");
    DestroyWindow(root);
    std::cout << "PASS: material fallback, 32 material rebuilds, failure-safe "
                 "root/child alpha, Mica fallback, recovery and disable\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
