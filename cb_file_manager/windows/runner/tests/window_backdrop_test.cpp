// Native API regression tests, independent of Flutter and app E2E.
#include <windows.h>
#include <dwmapi.h>
#include <cstring>
#include <iostream>
#include <map>
#include <stdexcept>
#include <vector>
#include "../startup_visibility.h"
#include "../custom_frame_message.h"
#include "../window_backdrop_frame.h"

namespace {
bool material_ok = true, accent_ok = true;
bool child_accent_ok = true;
bool acrylic_accent_ok = true;
int legacy_acrylic_calls = 0, legacy_blur_calls = 0, transparent_calls = 0;
int attribute_calls = 0, accent_calls = 0, redraw_calls = 0;
bool synchronous_redraw = false;
std::map<HWND, BOOL> alpha;
std::map<HWND, int> accents;
std::map<HWND, DWORD> accent_tints;
std::map<HWND, int> accent_disables;
std::vector<int> materials;
HRESULT WINAPI Attribute(HWND hwnd, DWORD id, LPCVOID value, DWORD) {
  ++attribute_calls;
  if (id == 38) {
    const int material = *static_cast<const int*>(value);
    materials.push_back(material);
    if (material != 1 && !material_ok) return E_FAIL;
  }
  if (id == 1029 && !material_ok) return E_FAIL;
  if (id == 39) alpha[hwnd] = *static_cast<const BOOL*>(value);
  return S_OK;
}
BOOL WINAPI Accent(HWND hwnd, void* raw) {
  ++accent_calls;
  struct Composition { int attribute; void* data; SIZE_T size; };
  struct Policy { int state; DWORD flags; DWORD tint; DWORD animation; };
  const auto& policy = *static_cast<const Policy*>(static_cast<Composition*>(raw)->data);
  const int state = policy.state;
  if (state == 0) ++accent_disables[hwnd];
  if (state == 2) ++transparent_calls;
  if (state == 4) ++legacy_acrylic_calls;
  if (state == 3) ++legacy_blur_calls;
  const bool accepted = state == 0 ||
      (accent_ok && (state != 4 || acrylic_accent_ok) &&
       (child_accent_ok || (GetWindowLongPtr(hwnd, GWL_STYLE) & WS_CHILD) == 0));
  if (state == 4 && policy.flags != 0) throw std::runtime_error("Acrylic accent has gradient flags");
  if (accepted) {
    accents[hwnd] = state;
    accent_tints[hwnd] = policy.tint;
  }
  return accepted;
}
BOOL WINAPI Redraw(HWND, const RECT*, HRGN, UINT flags) {
  ++redraw_calls;
  synchronous_redraw |= (flags & (RDW_UPDATENOW | RDW_ERASENOW)) != 0;
  return TRUE;
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

bool startup_held = true;
WNDPROC original_proc = nullptr;
LRESULT CALLBACK StartupProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  return DispatchCustomFrameMessage(hwnd, message, wparam, lparam,
      [&](LPARAM forwarded) {
        if (message == WM_WINDOWPOSCHANGING) {
          HoldStartupVisibility(startup_held, reinterpret_cast<WINDOWPOS*>(forwarded));
        }
        return CallWindowProcW(original_proc, hwnd, message, wparam, forwarded);
      });
}
}  // namespace

#define DwmSetWindowAttribute Attribute
#define GetProcAddress Lookup
#define RedrawWindow Redraw
#include "../window_backdrop.h"
#undef RedrawWindow
#undef GetProcAddress
#undef DwmSetWindowAttribute
#include "../window_backdrop_diagnostics.h"

int main() {
  try {
    const HWND root = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        L"STATIC", L"Backdrop test", WS_OVERLAPPEDWINDOW,
        -32000, -32000, 400, 300, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    const HWND child = CreateWindowExW(0, L"STATIC", L"", WS_CHILD,
        0, 0, 400, 300, root, nullptr, GetModuleHandleW(nullptr), nullptr);
    Check(root && child, "Could not create native backdrop receivers");

    // Exercise the real ShowWindow/SC_MAXIMIZE path used by window_manager,
    // without Flutter or an app E2E run. Layout must settle while still hidden.
    original_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
        root, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&StartupProc)));
    SendMessageW(root, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
    Check(!IsWindowVisible(root) && IsZoomed(root),
          "Startup maximize exposed the window before Flutter's first frame");
    startup_held = false;
    ShowWindow(root, SW_SHOW);
    Check(IsWindowVisible(root) && IsZoomed(root),
          "First-frame reveal lost the prepared maximized layout");
    ShowWindow(root, SW_HIDE);
    SetWindowLongPtrW(root, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(original_proc));

    // Current Windows can accept the root's material while rejecting accent
    // policies on the Flutter child. That must not cause endless root rebuilds.
    child_accent_ok = false;
    WindowBackdrop::State unsupported_child;
    Check(WindowBackdrop::Sync(unsupported_child, root, child, 26300, true, true, false),
          "Unsupported child accent incorrectly invalidated the working root material");
    Check(accents[root] == 4 && alpha[root] && unsupported_child.accent_acrylic &&
              materials.back() == 1 && accent_tints[root] == 0x01FFFFFF,
          "Acrylic was replaced by a transparent gradient or stacked with a system material");
    materials.clear();
    WindowBackdrop::Sync(unsupported_child, root, child, 26300, true, true, false);
    Check(materials.empty(), "Unsupported child accent triggered a root material rebuild");
    // Activation must restore the root without retrying a rejected child.
    unsupported_child.child_transparency_lost = true;
    const int unsupported_accents = accent_calls;
    accents[root] = 0;
    alpha[root] = FALSE;
    Check(WindowBackdrop::Sync(unsupported_child, root, child, 26300, true, true, false) &&
              accent_calls == unsupported_accents + 1 && accents[root] == 4 &&
              alpha[root] && !unsupported_child.child_transparency_lost,
          "Activation failed root transparency or retried a rejected child");
    child_accent_ok = true;
    // A colorization change resets only the dark-mode tint: restore it in place.
    unsupported_child.dark_mode_lost = true;
    materials.clear();
    const int dark_attributes = attribute_calls;
    Check(WindowBackdrop::Sync(unsupported_child, root, child, 26300, true, true, false) &&
              materials.empty() && attribute_calls == dark_attributes + 1 &&
              !unsupported_child.dark_mode_lost,
          "Restoring the dark-mode tint rebuilt the material");

    // An unavailable accent API uses the system material alone, without
    // overwriting it with a transparent-gradient root policy afterwards.
    acrylic_accent_ok = false;
    materials.clear();
    WindowBackdrop::State system_fallback;
    Check(WindowBackdrop::Sync(system_fallback, root, child, 26300, true, true, false) &&
              !system_fallback.accent_acrylic && materials.back() == 3 && accents[root] == 0,
          "System acrylic fallback was stacked with a root accent");
    system_fallback.child_transparency_lost = true;
    const int fallback_accents = accent_calls;
    WindowBackdrop::Sync(system_fallback, root, child, 26300, true, true, false);
    Check(accents[root] == 0 && accent_calls == fallback_accents + 1,
          "System material recovery installed a transparent-gradient root accent");
    acrylic_accent_ok = true;

    // A failed DWM material API must not stop the independent accent path.
    material_ok = false;
    const int legacy_acrylic_before = legacy_acrylic_calls;
    Check(WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, false),
          "Legacy acrylic fallback failed");
    Check(legacy_acrylic_calls == legacy_acrylic_before + 1,
          "Failed DWM material prevented the independent acrylic accent");

    // A previous working material may disappear after minimize/restore.
    material_ok = true;
    Check(WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, true),
          "Could not initialize acrylic");
    Check(alpha[root] && alpha[child], "Working acrylic did not expose the material");
    for (int i = 0; i < 32; ++i) {
      materials.clear();
      Check(WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, i % 2),
            "Repeated material restore failed");
      Check(materials.size() == 1 && materials[0] == 1 && accents[root] == 4,
            "Acrylic installation stacked two root material paths");
    }

    // Unchanged retry requests must not dirty either composition surface.
    WindowBackdrop::State state;
    materials.clear();
    Check(WindowBackdrop::Sync(state, root, child, 26100, true, true, true) &&
              !materials.empty() && materials[0] == 1,
          "First sync did not build the material");
    for (int i = 0; i < 32; ++i) {
      materials.clear();
      const int attributes_before = attribute_calls;
      const int accents_before = accent_calls;
      const int redraws_before = redraw_calls;
      Check(WindowBackdrop::Sync(state, root, child, 26100, true, true, true),
            "Repeated sync failed");
      Check(materials.empty(), "A repeated sync cleared the working material");
      Check(attribute_calls == attributes_before && accent_calls == accents_before &&
                redraw_calls == redraws_before,
            "An unchanged sync dirtied a working composition surface");
    }
    // Maximize/restore may present a new Flutter surface AFTER a timer would
    // have restored acrylic. Do not cache that early repair as final.
    WindowBackdrop::ResizeFrameSync frames;
    const int disables_before_resize = accent_disables[root];
    for (int i = 0; i < 32; ++i) {
      const WPARAM size_type = i % 2 ? SIZE_RESTORED : SIZE_MAXIMIZED;
      const LPARAM size = i % 2 ? MAKELPARAM(1200, 800) : MAKELPARAM(1920, 1080);
      Check(frames.OnSize(root, size_type, size) &&
                WindowBackdrop::IsResizeFramePending(root),
            "Resize did not defer backdrop repair until its rendered frame");
      const WPARAM stale = frames.generation();
      materials.clear();
      state.material_lost = true;
      Check(!WindowBackdrop::ShouldDeferSizeMoveRepair(state, true),
            "Acrylic repair waited for mouse-up after a drag restored the window");
      // Same gate used by the plugin's timer callback.
      if (!WindowBackdrop::IsResizeFramePending(root)) {
        WindowBackdrop::Sync(state, root, child, 26100, true, true, true);
      }
      Check(materials.empty(), "Timer rebuilt acrylic before the resize frame");
      // A second size supersedes the first callback, and presentation resets
      // both alpha receivers (the opaque surface that hides the material).
      const LPARAM final_size = MAKELPARAM(LOWORD(size) - 1, HIWORD(size));
      frames.OnSize(root, size_type, final_size);
      alpha[root] = alpha[child] = FALSE;
      Check(!frames.OnFrame(root, stale) &&
                WindowBackdrop::IsResizeFramePending(root),
            "Stale frame prematurely released backdrop repair");
      Check(frames.OnFrame(root, frames.generation()) &&
                !WindowBackdrop::IsResizeFramePending(root),
            "Rendered resize frame did not release backdrop repair");
      Check(WindowBackdrop::Sync(state, root, child, 26100, true, true, true) &&
                alpha[root] && alpha[child] && materials.empty() && accents[root] == 4 &&
                accent_disables[root] == disables_before_resize,
            "Rendered maximize/restore did not recover material and alpha");
      Check(!frames.OnFrame(root, frames.generation()) &&
                !frames.OnSize(root, size_type, final_size),
            "Repeated frame or same-size title refresh invalidated acrylic");
      materials.clear();
      WindowBackdrop::Sync(state, root, child, 26100, true, true, true);
      Check(materials.empty(), "Resize recovery rebuilt acrylic more than once");
    }
    frames.OnSize(root, SIZE_MAXIMIZED, MAKELPARAM(1920, 1080));
    system_fallback.material_lost = true;
    Check(WindowBackdrop::ShouldDeferSizeMoveRepair(system_fallback, true) &&
              !WindowBackdrop::ShouldDeferSizeMoveRepair(system_fallback, false),
          "System material fallback did not wait for the native drag to finish");
    const WPARAM before_minimize = frames.generation();
    Check(!frames.OnSize(root, SIZE_MINIMIZED, 0) &&
              !frames.OnFrame(root, before_minimize) &&
              !WindowBackdrop::IsResizeFramePending(root),
          "Minimize left a pending frame or accepted an older callback");
    // Activation may invalidate only the child. Repair once without replacing
    // the root material, and keep the retry timers completely idle afterwards.
    state.child_transparency_lost = true;
    alpha[child] = FALSE;
    const int transparent_before = transparent_calls;
    const int acrylic_before = legacy_acrylic_calls;
    Check(WindowBackdrop::Sync(state, root, child, 26100, true, true, true) &&
              alpha[root] && alpha[child] && transparent_calls == transparent_before + 1 &&
              legacy_acrylic_calls == acrylic_before + 1 && accents[root] == 4 &&
              materials.empty() && !state.child_transparency_lost,
          "Activation did not restore only the lost child transparency");
    WindowBackdrop::Sync(state, root, child, 26100, true, true, true);
    Check(transparent_calls == transparent_before + 1 && legacy_acrylic_calls == acrylic_before + 1,
          "A retry re-applied transparency after activation already restored it");
    state.child_transparency_lost = true;
    accent_ok = false;
    Check(!WindowBackdrop::Sync(state, root, child, 26100, true, true, true) &&
              state.child_transparency_lost,
          "Failed child recovery was incorrectly cached as healthy");
    accent_ok = true;
    Check(WindowBackdrop::Sync(state, root, child, 26100, true, true, true) &&
              !state.child_transparency_lost && materials.empty(),
          "A failed child recovery was not retried independently of the material");
    // Minimize/resize repairs the accent once, without a transparent/solid gap.
    state.material_lost = true;
    materials.clear();
    Check(WindowBackdrop::Sync(state, root, child, 26100, true, true, true) &&
              materials.empty() && accents[root] == 4 && !state.material_lost,
          "A lost acrylic accent was cleared instead of repaired in place");
    materials.clear();
    WindowBackdrop::Sync(state, root, child, 26100, true, true, true);
    Check(materials.empty(), "A rebuilt material was rebuilt again");
    materials.clear();
    WindowBackdrop::Sync(state, root, child, 26100, true, true, false);
    Check(!materials.empty() && materials[0] == 1,
          "A theme change did not rebuild the material");
    // Windows 10 uses the same event-driven repair; idle timers do no work.
    const int legacy_before = legacy_acrylic_calls;
    WindowBackdrop::Sync(state, root, child, 19045, true, true, false);
    WindowBackdrop::Sync(state, root, child, 19045, true, true, false);
    Check(legacy_acrylic_calls == legacy_before,
          "An idle legacy accent backdrop was unnecessarily reapplied");
    // A rebuild that fails after a lost material is retried by the next sync.
    state.material_lost = true;
    material_ok = accent_ok = false;
    Check(!WindowBackdrop::Sync(state, root, child, 26100, true, true, false),
          "A failed sync reported success");
    material_ok = accent_ok = true;
    materials.clear();
    Check(WindowBackdrop::Sync(state, root, child, 26100, true, true, false) &&
              materials.empty() && accents[root] == 4 && !state.material_lost,
          "A failed material was not retried");

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
    materials.clear();
    WindowBackdrop::State mica;
    Check(WindowBackdrop::Sync(mica, root, child, 26300, true, false, true) &&
              !mica.accent_acrylic && materials.back() == 2 && accents[root] == 0,
          "Mica did not use the independent system backdrop path");
    materials.clear();
    Check(WindowBackdrop::Sync(mica, root, child, 26300, true, true, true) &&
              mica.accent_acrylic && materials.size() == 1 && materials.back() == 1 &&
              accents[root] == 4 && accent_tints[root] == 0x01222222,
          "Switching Mica to acrylic left two root materials or a dark opaque tint");
    Check(WindowBackdrop::ApplyToWindow(root, child, 26100, true, true, false),
          "Backdrop did not recover after a transient API failure");
    Check(WindowBackdrop::ApplyToWindow(root, child, 26100, false, true, false),
          "Wallpaper mode could not disable the native backdrop");
    Check(!alpha[root] && !alpha[child] && materials.back() == 1,
          "Disabled backdrop retained alpha or a material");
    Check(!synchronous_redraw,
          "Backdrop forced a paint before root and child updates completed");
    DestroyWindow(root);
    std::cout << "PASS: hidden startup maximize and first-frame reveal with custom frame, "
                 "exclusive acrylic/system backends, translucent native tint, "
                 "32 frame-synchronized resize repairs without material clears, "
                 "acrylic repair while dragging with deferred system fallback, "
                 "32 idle no-ops, unsupported child, failure-safe alpha, "
                 "Mica/system fallback, recovery and disable\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
