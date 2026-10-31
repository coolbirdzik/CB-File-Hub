#ifndef RUNNER_WINDOW_BACKDROP_H_
#define RUNNER_WINDOW_BACKDROP_H_

#include <windows.h>
#include <dwmapi.h>

// SDK-only backdrop implementation shared by the runner and native regression tests.
namespace WindowBackdrop {
  typedef enum _WINDOWCOMPOSITIONATTRIB
  {
    WCA_UNDEFINED = 0,
    WCA_NCRENDERING_ENABLED = 1,
    WCA_NCRENDERING_POLICY = 2,
    WCA_TRANSITIONS_FORCEDISABLED = 3,
    WCA_ALLOW_NCPAINT = 4,
    WCA_CAPTION_BUTTON_BOUNDS = 5,
    WCA_NONCLIENT_RTL_LAYOUT = 6,
    WCA_FORCE_ICONIC_REPRESENTATION = 7,
    WCA_EXTENDED_FRAME_BOUNDS = 8,
    WCA_HAS_ICONIC_BITMAP = 9,
    WCA_THEME_ATTRIBUTES = 10,
    WCA_NCRENDERING_EXILED = 11,
    WCA_NCADORNMENTINFO = 12,
    WCA_EXCLUDED_FROM_LIVEPREVIEW = 13,
    WCA_VIDEO_OVERLAY_ACTIVE = 14,
    WCA_FORCE_ACTIVEWINDOW_APPEARANCE = 15,
    WCA_DISALLOW_PEEK = 16,
    WCA_CLOAK = 17,
    WCA_CLOAKED = 18,
    WCA_ACCENT_POLICY = 19,
    WCA_FREEZE_REPRESENTATION = 20,
    WCA_EVER_UNCLOAKED = 21,
    WCA_VISUAL_OWNER = 22,
    WCA_HOLOGRAPHIC = 23,
    WCA_EXCLUDED_FROM_DDA = 24,
    WCA_PASSIVEUPDATEMODE = 25,
    WCA_USEDARKMODECOLORS = 26,
    WCA_LAST = 27
  } WINDOWCOMPOSITIONATTRIB;

  typedef struct _WINDOWCOMPOSITIONATTRIBDATA
  {
    WINDOWCOMPOSITIONATTRIB Attrib;
    PVOID pvData;
    SIZE_T cbData;
  } WINDOWCOMPOSITIONATTRIBDATA;

  typedef enum _ACCENT_STATE
  {
    ACCENT_DISABLED = 0,
    ACCENT_ENABLE_GRADIENT = 1,
    ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
    ACCENT_ENABLE_BLURBEHIND = 3,
    ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
    ACCENT_ENABLE_HOSTBACKDROP = 5,
    ACCENT_INVALID_STATE = 6
  } ACCENT_STATE;

  typedef struct _ACCENT_POLICY
  {
    ACCENT_STATE AccentState;
    DWORD AccentFlags;
    DWORD GradientColor;
    DWORD AnimationId;
  } ACCENT_POLICY;

  typedef BOOL(WINAPI *SetWindowCompositionAttribute)(
      HWND, WINDOWCOMPOSITIONATTRIBDATA *);

  constexpr DWORD kDwmwaUseHostBackdropBrush = 17;
  constexpr DWORD kDwmwaSystemBackdropType = 38;
  constexpr DWORD kDwmsbtNone = 1;
  constexpr DWORD kDwmsbtMainWindow = 2;
  constexpr DWORD kDwmsbtTransientWindow = 3;
  constexpr DWORD kWindowAttributeUseImmersiveDarkMode = 20;
  constexpr DWORD kWindowAttributeCaptionColor = 35;
  constexpr DWORD kWindowAttributeMicaEffect = 1029;
  constexpr DWORD kDwmwaRedirectionBitmapAlpha = 39;


  static HMODULE g_user32_module = nullptr;
  static SetWindowCompositionAttribute g_set_window_composition_attribute = nullptr;

  inline bool EnsureSetWindowCompositionAttributeLoaded()
  {
    if (g_set_window_composition_attribute != nullptr)
      return true;

    g_user32_module = ::GetModuleHandleA("user32.dll");
    if (!g_user32_module)
      return false;

    g_set_window_composition_attribute =
        reinterpret_cast<SetWindowCompositionAttribute>(
            ::GetProcAddress(g_user32_module, "SetWindowCompositionAttribute"));
    return g_set_window_composition_attribute != nullptr;
  }

  inline bool ApplyAccentPolicy(HWND hwnd, ACCENT_STATE state, DWORD gradient_color = 0)
  {
    if (!hwnd)
      return false;
    if (!EnsureSetWindowCompositionAttributeLoaded())
      return false;

    ACCENT_POLICY accent = {
        state,
        state == ACCENT_ENABLE_ACRYLICBLURBEHIND ? 0u : 2u,
        gradient_color,
        0,
    };
    WINDOWCOMPOSITIONATTRIBDATA data;
    data.Attrib = WCA_ACCENT_POLICY;
    data.pvData = &accent;
    data.cbData = sizeof(accent);
    return g_set_window_composition_attribute(hwnd, &data) != FALSE;
  }

  inline void SetRedirectionBitmapAlpha(HWND hwnd, DWORD build_number, bool enabled)
  {
    if (!hwnd || build_number < 26100)
      return;

    const BOOL enable_alpha = enabled ? TRUE : FALSE;
    ::DwmSetWindowAttribute(
        hwnd, kDwmwaRedirectionBitmapAlpha, &enable_alpha,
        sizeof(enable_alpha));
  }

  inline bool SetFlutterChildBackdropTransparency(HWND hwnd, DWORD build_number, bool enabled)
  {
    if (!hwnd)
      return false;

    SetRedirectionBitmapAlpha(hwnd, build_number, enabled);
    const bool applied = ApplyAccentPolicy(
        hwnd, enabled ? ACCENT_ENABLE_TRANSPARENTGRADIENT : ACCENT_DISABLED);
    ::RedrawWindow(
        hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME);
    return applied;
  }

  inline bool SetLegacyBlurBehind(HWND hwnd, bool enabled)
  {
    if (!hwnd)
      return false;

    DWM_BLURBEHIND blur = {};
    blur.dwFlags = DWM_BB_ENABLE;
    blur.fEnable = enabled ? TRUE : FALSE;
    blur.hRgnBlur = nullptr;
    blur.fTransitionOnMaximized = FALSE;

    return SUCCEEDED(::DwmEnableBlurBehindWindow(hwnd, &blur));
  }

  inline bool SetAcrylicAccent(HWND hwnd, bool dark)
  {
    // Acrylic requires nonzero tint alpha. Flutter already owns the user's
    // tint/strength, so do not stack a second opaque native tint over it.
    return ApplyAccentPolicy(hwnd, ACCENT_ENABLE_ACRYLICBLURBEHIND,
                             dark ? 0x01222222 : 0x01FFFFFF);
  }

  inline bool Apply(
      HWND hwnd, DWORD build_number, bool enabled, bool prefer_acrylic, bool is_dark_mode,
      bool* accent_acrylic_applied = nullptr)
  {
    if (accent_acrylic_applied) *accent_acrylic_applied = false;
    if (!hwnd)
      return false;

    // Clear old composition only when installing/changing the effect. Sync
    // repairs an existing acrylic accent in place on resize and activation.
    ApplyAccentPolicy(hwnd, ACCENT_DISABLED);
    SetLegacyBlurBehind(hwnd, false);

    if (!enabled)
    {
      const BOOL disable_host_backdrop = FALSE;
      ::DwmSetWindowAttribute(
          hwnd, kDwmwaUseHostBackdropBrush, &disable_host_backdrop,
          sizeof(disable_host_backdrop));

      const DWORD none_backdrop = kDwmsbtNone;
      ::DwmSetWindowAttribute(
          hwnd, kDwmwaSystemBackdropType, &none_backdrop, sizeof(none_backdrop));

      const BOOL disable = FALSE;
      ::DwmSetWindowAttribute(
          hwnd, kWindowAttributeUseImmersiveDarkMode, &disable, sizeof(disable));
      ::DwmSetWindowAttribute(
          hwnd, kWindowAttributeMicaEffect, &disable, sizeof(disable));

      SetRedirectionBitmapAlpha(hwnd, build_number, false);
      ::RedrawWindow(
          hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME);
      return true;
    }

    bool applied = false;
    if (prefer_acrylic)
    {
      // The transient system backdrop and a transparent-gradient root accent
      // are different composition paths. Do not stack them. Use one root
      // acrylic accent for Flutter's HWND-backed swapchain, including Win11.
      const BOOL disable_host_backdrop = FALSE;
      ::DwmSetWindowAttribute(hwnd, kDwmwaUseHostBackdropBrush,
                              &disable_host_backdrop, sizeof(disable_host_backdrop));
      if (build_number >= 22621) {
        const DWORD none = kDwmsbtNone;
        ::DwmSetWindowAttribute(hwnd, kDwmwaSystemBackdropType, &none, sizeof(none));
      } else if (build_number >= 22000) {
        const BOOL disable_mica = FALSE;
        ::DwmSetWindowAttribute(hwnd, kWindowAttributeMicaEffect,
                                &disable_mica, sizeof(disable_mica));
      }
      const MARGINS shadow = {0, 0, 1, 0};
      ::DwmExtendFrameIntoClientArea(hwnd, &shadow);
      applied = SetAcrylicAccent(hwnd, is_dark_mode);
      if (accent_acrylic_applied) *accent_acrylic_applied = applied;
    }

    // Keep the supported DWM path for Mica, or if acrylic accents are rejected.
    if (!applied && build_number >= 22621)
    {
      const BOOL enable_dark = is_dark_mode ? TRUE : FALSE;
      const COLORREF kColorNone = 0xFFFFFFFE;
      const MARGINS glass_sheet = {-1};
      const BOOL enable_host_backdrop = prefer_acrylic ? TRUE : FALSE;
      const INT backdrop_type =
          prefer_acrylic ? static_cast<INT>(kDwmsbtTransientWindow)
                         : static_cast<INT>(kDwmsbtMainWindow);

      ::DwmExtendFrameIntoClientArea(hwnd, &glass_sheet);
      ::DwmSetWindowAttribute(
          hwnd, kWindowAttributeUseImmersiveDarkMode, &enable_dark,
          sizeof(enable_dark));
      ::DwmSetWindowAttribute(
          hwnd, kWindowAttributeCaptionColor, &kColorNone, sizeof(kColorNone));

      ::DwmSetWindowAttribute(
          hwnd, kDwmwaUseHostBackdropBrush, &enable_host_backdrop,
          sizeof(enable_host_backdrop));
      const HRESULT backdrop_hr = ::DwmSetWindowAttribute(
          hwnd, kDwmwaSystemBackdropType, &backdrop_type, sizeof(backdrop_type));

      // Enabling host brushes alone does not draw a material.
      applied = SUCCEEDED(backdrop_hr);
    }
    else if (!applied && build_number >= 22000 && !prefer_acrylic)
    {
      // Windows 11 21H2 Mica fallback.
      const BOOL enable_dark_mode = is_dark_mode ? TRUE : FALSE;
      const BOOL enable_mica = TRUE;
      const MARGINS glass_sheet = {-1};
      ::DwmExtendFrameIntoClientArea(hwnd, &glass_sheet);
      ::DwmSetWindowAttribute(
          hwnd, kWindowAttributeUseImmersiveDarkMode, &enable_dark_mode,
          sizeof(enable_dark_mode));
      const HRESULT mica_hr = ::DwmSetWindowAttribute(
          hwnd, kWindowAttributeMicaEffect, &enable_mica, sizeof(enable_mica));
      applied = SUCCEEDED(mica_hr);
    }

    if (!applied && !prefer_acrylic)
      applied = ApplyAccentPolicy(hwnd, ACCENT_ENABLE_BLURBEHIND);

    // Never overwrite a root acrylic accent with TRANSPARENTGRADIENT. Child
    // transparency is a separate, optional compatibility request below.
    // Never leave an alpha-enabled root behind if all material APIs failed.
    SetRedirectionBitmapAlpha(hwnd, build_number, applied);

    // Do not force a synchronous paint while the child still has its previous
    // alpha/accent state. Let DWM compose after both surfaces are updated.
    ::RedrawWindow(hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME);
    return applied;
  }

  inline bool ApplyToWindow(HWND root, HWND view, DWORD build_number,
                             bool enabled, bool prefer_acrylic, bool dark) {
    const bool applied = Apply(root, build_number, enabled, prefer_acrylic, dark);
    if (view && view != root) {
      // Some Windows builds reject accent policies on child HWNDs. The root
      // still owns a valid system material; do not clear/rebuild it on every
      // recovery timer merely because this compatibility request was rejected.
      SetFlutterChildBackdropTransparency(
          view, build_number, enabled && prefer_acrylic && applied);
    }
    return applied;
  }

  // What one window last applied. Every rebuild clears the material for a
  // frame, so focus changes and repeated requests must not rebuild it.
  struct State
  {
    bool applied = false;
    bool enabled = false;
    bool prefer_acrylic = false;
    bool dark = false;
    // Minimize and resize can discard the material while DWM keeps its enum.
    bool material_lost = true;
    // Activation can reset root/child transparency independently of the
    // material. Repair once without rebuilding the system backdrop.
    bool child_transparency_lost = false;
    // The child rejected its accent while the root material was rebuilt.
    // Current builds do this permanently; activations must not retry it.
    bool child_transparency_unsupported = false;
    // The runner resets immersive dark mode from the system theme on
    // colorization changes. Restore the app's value without a rebuild.
    bool dark_mode_lost = false;
    bool accent_acrylic = false;
  };

  inline bool ShouldDeferSizeMoveRepair(const State& state, bool in_size_move)
  {
    // Acrylic is repaired in place, so waiting for mouse-up leaves the
    // restored Flutter surface without blur for the entire drag. Only a
    // system-material rebuild needs the old size/move-loop delay.
    return in_size_move && state.material_lost && !state.accent_acrylic;
  }

  // Settings changes install a new material. Resizing/activation repair an
  // existing acrylic accent without clearing it or toggling the DWM material.
  inline bool Sync(State &state, HWND root, HWND view, DWORD build_number,
                   bool enabled, bool prefer_acrylic, bool dark)
  {
    if (state.applied && (!state.material_lost || state.accent_acrylic) &&
        state.enabled == enabled && state.prefer_acrylic == prefer_acrylic &&
        state.dark == dark)
    {
      if (enabled && state.dark_mode_lost)
      {
        const BOOL enable_dark = dark ? TRUE : FALSE;
        ::DwmSetWindowAttribute(root, kWindowAttributeUseImmersiveDarkMode,
                                &enable_dark, sizeof(enable_dark));
        state.dark_mode_lost = false;
      }
      if (enabled && prefer_acrylic &&
          (state.child_transparency_lost || state.material_lost))
      {
        SetRedirectionBitmapAlpha(root, build_number, true);
        const bool root_restored = !state.accent_acrylic || SetAcrylicAccent(root, dark);
        bool restored = root_restored;
        if (view && view != root && !state.child_transparency_unsupported) {
          restored = SetFlutterChildBackdropTransparency(view, build_number, true) && restored;
        }
        ::RedrawWindow(root, nullptr, nullptr, RDW_INVALIDATE);
        state.material_lost = !root_restored;
        state.child_transparency_lost = !restored;
        return restored;
      }
      return true;
    }
    bool accent_acrylic = false;
    const bool applied = Apply(root, build_number, enabled, prefer_acrylic, dark,
                               &accent_acrylic);
    bool child_unsupported = false;
    if (view && view != root)
    {
      // Some Windows builds reject accent policies on child HWNDs. The root
      // still owns a valid system material; do not clear/rebuild it on every
      // recovery timer merely because this compatibility request was rejected.
      const bool child_enabled = enabled && prefer_acrylic && applied;
      child_unsupported =
          !SetFlutterChildBackdropTransparency(view, build_number, child_enabled) &&
          child_enabled;
    }
    state = {applied, enabled, prefer_acrylic, dark, false, false,
             child_unsupported, false, accent_acrylic};
    return applied;
  }

}  // namespace WindowBackdrop

#endif  // RUNNER_WINDOW_BACKDROP_H_
