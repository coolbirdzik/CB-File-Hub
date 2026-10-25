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
        2,
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

  inline void SetFlutterChildBackdropTransparency(HWND hwnd, DWORD build_number, bool enabled)
  {
    if (!hwnd)
      return;

    SetRedirectionBitmapAlpha(hwnd, build_number, enabled);
    ApplyAccentPolicy(hwnd, enabled ? ACCENT_ENABLE_TRANSPARENTGRADIENT
                                    : ACCENT_DISABLED);
    ::RedrawWindow(
        hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW | RDW_FRAME);
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

  inline bool Apply(
      HWND hwnd, DWORD build_number, bool enabled, bool prefer_acrylic, bool is_dark_mode)
  {
    if (!hwnd)
      return false;

    // Persist for the window proc delegate to re-apply on WM_ACTIVATE etc.


    // Clear accent state first. This mirrors flutter_acrylic behavior and avoids
    // stale composition artifacts when switching effects.
    ApplyAccentPolicy(hwnd, ACCENT_DISABLED);

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
      SetLegacyBlurBehind(hwnd, false);
      ::RedrawWindow(
          hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW | RDW_FRAME);
      return true;
    }

    bool applied = false;

    // Windows 11 22H2+ modern system backdrops.
    if (build_number >= 22621)
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
      // Resize/minimize can discard the material while retaining its enum.
      // Rebuild it explicitly instead of setting the same cached value again.
      const DWORD no_backdrop = kDwmsbtNone;
      ::DwmSetWindowAttribute(hwnd, kDwmwaSystemBackdropType, &no_backdrop,
                              sizeof(no_backdrop));
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

    if (!applied)
    {
      // Legacy approach from flutter_acrylic for pre-Windows 11 systems.
      // Here ACCENT_DISABLED was already called above to clear stale state.
      if (prefer_acrylic)
      {
        // ARGB format (AABBGGRR). Fallback for Windows 10 / early Windows 11.
        const DWORD kLegacyAcrylicTint =
            is_dark_mode ? 0x99222222 : 0x99FFFFFF;
        applied = ApplyAccentPolicy(
            hwnd, ACCENT_ENABLE_ACRYLICBLURBEHIND, kLegacyAcrylicTint);
      }
      else
      {
        applied = ApplyAccentPolicy(hwnd, ACCENT_ENABLE_BLURBEHIND);
      }
    }

    // Avoid stacking legacy blur with modern system backdrops.
    if (applied)
    {
      SetLegacyBlurBehind(hwnd, false);
    }
    else
    {
      SetLegacyBlurBehind(hwnd, enabled);
    }

    // Never leave an alpha-enabled root behind if all material APIs failed.
    SetRedirectionBitmapAlpha(hwnd, build_number, applied);

    ::RedrawWindow(
        hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW | RDW_FRAME);
    return applied;
  }

  inline bool ApplyToWindow(HWND root, HWND view, DWORD build_number,
                             bool enabled, bool prefer_acrylic, bool dark) {
    const bool applied = Apply(root, build_number, enabled, prefer_acrylic, dark);
    if (view && view != root) {
      SetFlutterChildBackdropTransparency(
          view, build_number, enabled && prefer_acrylic && applied);
    }
    return applied;
  }

}  // namespace WindowBackdrop

#endif  // RUNNER_WINDOW_BACKDROP_H_
