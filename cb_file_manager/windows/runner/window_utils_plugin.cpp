#include "window_utils_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <dwmapi.h>
#include <ole2.h>
#include <shellapi.h>
#include <shlobj.h>

#include <memory>
#include <string>
#include <vector>
#include <cstring>
#include <atomic>
#include <thread>

namespace
{

  static bool g_is_fullscreen = false;
  static RECT g_frame_before_fullscreen = {0, 0, 0, 0};
  static LONG_PTR g_style_before_fullscreen = 0;
  static bool g_maximized_before_fullscreen = false;

  static bool g_ole_initialized = false;
  static UINT g_cf_tab_payload = 0;
  static UINT g_cf_tab_source_pid = 0;
  static UINT g_cf_preferred_drop_effect = 0;
  static std::atomic<bool> g_tab_window_drag_active{false};
  constexpr DWORD kTabWindowDragPollIntervalMs = 8;

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

  typedef LONG NTSTATUS, *PNTSTATUS;
  typedef NTSTATUS(WINAPI *RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);
#define STATUS_SUCCESS (0x00000000)

  constexpr DWORD kDwmwaUseHostBackdropBrush = 17;
  constexpr DWORD kDwmwaSystemBackdropType = 38;
  constexpr DWORD kDwmsbtNone = 1;
  constexpr DWORD kDwmsbtMainWindow = 2;
  constexpr DWORD kDwmsbtTransientWindow = 3;
  constexpr DWORD kWindowAttributeUseImmersiveDarkMode = 20;
  constexpr DWORD kWindowAttributeCaptionColor = 35;
  constexpr DWORD kWindowAttributeMicaEffect = 1029;
  constexpr DWORD kDwmwaRedirectionBitmapAlpha = 39;

  static bool g_backdrop_enabled = false;
  static bool g_backdrop_prefer_acrylic = true;
  static bool g_backdrop_dark_mode = false;

  static HMODULE g_user32_module = nullptr;
  static SetWindowCompositionAttribute g_set_window_composition_attribute = nullptr;

  bool SetNativeSystemBackdrop(
      HWND hwnd, bool enabled, bool prefer_acrylic, bool is_dark_mode);
  HWND GetMainWindow(flutter::PluginRegistrarWindows *registrar);
  HWND GetTopLevelWindow(flutter::PluginRegistrarWindows *registrar);

  RTL_OSVERSIONINFOW GetWindowsVersionInfo()
  {
    HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
    if (ntdll)
    {
      RtlGetVersionPtr rtl_get_version_ptr =
          reinterpret_cast<RtlGetVersionPtr>(::GetProcAddress(ntdll, "RtlGetVersion"));
      if (rtl_get_version_ptr != nullptr)
      {
        RTL_OSVERSIONINFOW version_info = {0};
        version_info.dwOSVersionInfoSize = sizeof(version_info);
        if (STATUS_SUCCESS == rtl_get_version_ptr(&version_info))
        {
          return version_info;
        }
      }
    }

    RTL_OSVERSIONINFOW fallback = {0};
    return fallback;
  }

  bool EnsureSetWindowCompositionAttributeLoaded()
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

  bool ApplyAccentPolicy(HWND hwnd, ACCENT_STATE state, DWORD gradient_color = 0)
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

  void SetRedirectionBitmapAlpha(HWND hwnd, DWORD build_number, bool enabled)
  {
    if (!hwnd || build_number < 26100)
      return;

    const BOOL enable_alpha = enabled ? TRUE : FALSE;
    ::DwmSetWindowAttribute(
        hwnd, kDwmwaRedirectionBitmapAlpha, &enable_alpha,
        sizeof(enable_alpha));
  }

  void SetFlutterChildBackdropTransparency(HWND hwnd, DWORD build_number, bool enabled)
  {
    if (!hwnd)
      return;

    SetRedirectionBitmapAlpha(hwnd, build_number, enabled);
    ApplyAccentPolicy(hwnd, enabled ? ACCENT_ENABLE_TRANSPARENTGRADIENT
                                    : ACCENT_DISABLED);
    ::RedrawWindow(
        hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW | RDW_FRAME);
  }

  void ReapplyBackdropForPluginInstance(
      flutter::PluginRegistrarWindows *registrar,
      HWND hwnd,
      bool active,
      bool prefer_acrylic,
      bool dark_mode)
  {
    if (!registrar || !active)
      return;

    HWND root = hwnd ? ::GetAncestor(hwnd, GA_ROOT) : nullptr;
    HWND target = root ? root : hwnd;
    if (!target)
      target = GetTopLevelWindow(registrar);
    if (!target)
      return;

    SetNativeSystemBackdrop(target, active, prefer_acrylic, dark_mode);

    HWND flutter_view = GetMainWindow(registrar);
    if (flutter_view && flutter_view != target)
    {
      SetFlutterChildBackdropTransparency(
          flutter_view, GetWindowsVersionInfo().dwBuildNumber,
          active && prefer_acrylic);
    }
  }

  void ScheduleBackdropReapplyForPluginInstance(
      flutter::PluginRegistrarWindows *registrar,
      HWND hwnd,
      bool active,
      bool prefer_acrylic,
      bool dark_mode)
  {
    if (!active)
      return;

    ReapplyBackdropForPluginInstance(
        registrar, hwnd, active, prefer_acrylic, dark_mode);

    ::SetTimer(hwnd, 0xCBA1, 80, nullptr);
    ::SetTimer(hwnd, 0xCBA2, 240, nullptr);
    ::SetTimer(hwnd, 0xCBA3, 520, nullptr);
  }

  bool SetLegacyBlurBehind(HWND hwnd, bool enabled)
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

  bool SetNativeSystemBackdrop(
      HWND hwnd, bool enabled, bool prefer_acrylic, bool is_dark_mode)
  {
    if (!hwnd)
      return false;

    // Persist for the window proc delegate to re-apply on WM_ACTIVATE etc.
    g_backdrop_enabled = enabled;
    g_backdrop_prefer_acrylic = prefer_acrylic;
    g_backdrop_dark_mode = is_dark_mode;

    const RTL_OSVERSIONINFOW version = GetWindowsVersionInfo();
    const DWORD build_number = version.dwBuildNumber;

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
    if (build_number >= 22523)
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

      const HRESULT host_hr = ::DwmSetWindowAttribute(
          hwnd, kDwmwaUseHostBackdropBrush, &enable_host_backdrop,
          sizeof(enable_host_backdrop));
      const HRESULT backdrop_hr = ::DwmSetWindowAttribute(
          hwnd, kDwmwaSystemBackdropType, &backdrop_type, sizeof(backdrop_type));

      applied = SUCCEEDED(host_hr) || SUCCEEDED(backdrop_hr);

      if (applied)
      {
        SetRedirectionBitmapAlpha(hwnd, build_number, true);
      }
    }
    else if (!applied && build_number >= 22000 && !prefer_acrylic)
    {
      // Windows 11 21H2 Mica fallback.
      const BOOL enable_dark_mode = is_dark_mode ? TRUE : FALSE;
      const BOOL enable_mica = TRUE;
      const MARGINS glass_sheet = {-1};
      ::DwmExtendFrameIntoClientArea(hwnd, &glass_sheet);
      const HRESULT dark_hr = ::DwmSetWindowAttribute(
          hwnd, kWindowAttributeUseImmersiveDarkMode, &enable_dark_mode,
          sizeof(enable_dark_mode));
      const HRESULT mica_hr = ::DwmSetWindowAttribute(
          hwnd, kWindowAttributeMicaEffect, &enable_mica, sizeof(enable_mica));
      applied = SUCCEEDED(dark_hr) || SUCCEEDED(mica_hr);

      if (applied)
      {
        SetRedirectionBitmapAlpha(hwnd, build_number, true);
      }
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

    ::RedrawWindow(
        hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW | RDW_FRAME);
    return applied;
  }

  HWND GetMainWindow(flutter::PluginRegistrarWindows *registrar)
  {
    if (!registrar)
      return nullptr;
    auto view = registrar->GetView();
    if (!view)
      return nullptr;
    return view->GetNativeWindow();
  }

  HWND GetTopLevelWindow(flutter::PluginRegistrarWindows *registrar)
  {
    HWND hwnd = GetMainWindow(registrar);
    if (hwnd)
    {
      HWND root = ::GetAncestor(hwnd, GA_ROOT);
      if (root)
        return root;
      return hwnd;
    }

    // Fallback for unusual hosting setups.
    return ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
  }

  RECT GetCurrentMonitorRect(HWND hwnd)
  {
    RECT monitor_rect = {0, 0, 0, 0};
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {0};
    info.cbSize = sizeof(MONITORINFO);
    if (GetMonitorInfo(monitor, &info))
    {
      monitor_rect = info.rcMonitor;
    }
    return monitor_rect;
  }

  RECT GetCurrentMonitorWorkRect(HWND hwnd)
  {
    RECT work_rect = {0, 0, 0, 0};
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {0};
    info.cbSize = sizeof(MONITORINFO);
    if (GetMonitorInfo(monitor, &info))
    {
      work_rect = info.rcWork;
    }
    return work_rect;
  }

  void EnterFullscreen(HWND hwnd)
  {
    if (!hwnd)
      return;

    if (!g_is_fullscreen)
    {
      g_maximized_before_fullscreen = ::IsZoomed(hwnd);
      g_style_before_fullscreen = ::GetWindowLongPtr(hwnd, GWL_STYLE);
      ::GetWindowRect(hwnd, &g_frame_before_fullscreen);
    }

    g_is_fullscreen = true;

    const RECT monitor_rect = GetCurrentMonitorRect(hwnd);

    ::SetWindowLongPtr(hwnd, GWL_STYLE,
                       g_style_before_fullscreen & ~WS_OVERLAPPEDWINDOW);

    ::SetWindowPos(hwnd, HWND_TOP, monitor_rect.left, monitor_rect.top,
                   monitor_rect.right - monitor_rect.left,
                   monitor_rect.bottom - monitor_rect.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);

    ::ShowWindow(hwnd, SW_SHOW);
    ::SetForegroundWindow(hwnd);
  }

  void ExitFullscreen(HWND hwnd)
  {
    if (!hwnd)
      return;
    if (!g_is_fullscreen)
      return;

    g_is_fullscreen = false;

    ::SetWindowLongPtr(hwnd, GWL_STYLE, g_style_before_fullscreen);

    // Refresh the frame.
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_FRAMECHANGED);

    if (g_maximized_before_fullscreen)
    {
      ::PostMessage(hwnd, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
    }
    else
    {
      ::SetWindowPos(hwnd, nullptr, g_frame_before_fullscreen.left,
                     g_frame_before_fullscreen.top,
                     g_frame_before_fullscreen.right -
                         g_frame_before_fullscreen.left,
                     g_frame_before_fullscreen.bottom -
                         g_frame_before_fullscreen.top,
                     SWP_NOACTIVATE | SWP_NOZORDER);
    }

    ::ShowWindow(hwnd, SW_SHOW);
    ::SetForegroundWindow(hwnd);
  }

  HGLOBAL CopyBytesToHGlobal(const void *data, size_t len)
  {
    if (!data || len == 0)
      return nullptr;
    HGLOBAL h = ::GlobalAlloc(GMEM_MOVEABLE, len);
    if (!h)
      return nullptr;
    void *p = ::GlobalLock(h);
    if (!p)
    {
      ::GlobalFree(h);
      return nullptr;
    }
    memcpy(p, data, len);
    ::GlobalUnlock(h);
    return h;
  }

  std::wstring Utf8ToWide(const std::string &value)
  {
    if (value.empty())
      return std::wstring();
    const int count = ::MultiByteToWideChar(
        CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
        nullptr, 0);
    if (count <= 0)
      return std::wstring();
    std::wstring result(static_cast<size_t>(count), L'\0');
    ::MultiByteToWideChar(
        CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
        result.data(), count);
    return result;
  }

  std::string WideToUtf8(const std::wstring &value)
  {
    if (value.empty())
      return std::string();
    const int count = ::WideCharToMultiByte(
        CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
        nullptr, 0, nullptr, nullptr);
    if (count <= 0)
      return std::string();
    std::string result(static_cast<size_t>(count), '\0');
    ::WideCharToMultiByte(
        CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
        result.data(), count, nullptr, nullptr);
    return result;
  }

  HGLOBAL CreateDropFilesHGlobal(const std::vector<std::wstring> &paths)
  {
    size_t chars = 1;
    for (const auto &path : paths)
      chars += path.size() + 1;

    const SIZE_T bytes = sizeof(DROPFILES) + chars * sizeof(wchar_t);
    HGLOBAL h = ::GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes);
    if (!h)
      return nullptr;

    void *raw = ::GlobalLock(h);
    if (!raw)
    {
      ::GlobalFree(h);
      return nullptr;
    }

    auto *drop_files = reinterpret_cast<DROPFILES *>(raw);
    drop_files->pFiles = sizeof(DROPFILES);
    drop_files->fWide = TRUE;

    wchar_t *cursor = reinterpret_cast<wchar_t *>(
        reinterpret_cast<BYTE *>(raw) + sizeof(DROPFILES));
    for (const auto &path : paths)
    {
      memcpy(cursor, path.c_str(), path.size() * sizeof(wchar_t));
      cursor += path.size();
      *cursor++ = L'\0';
    }
    *cursor = L'\0';

    ::GlobalUnlock(h);
    return h;
  }

  class TabDataObject : public IDataObject
  {
  public:
    explicit TabDataObject(std::string payload)
        : payload_(std::move(payload)), source_pid_(::GetCurrentProcessId()) {}

    HRESULT __stdcall QueryInterface(REFIID riid,
                                     void **ppvObject) override
    {
      if (!ppvObject)
        return E_POINTER;
      *ppvObject = nullptr;
      if (riid == IID_IUnknown || riid == IID_IDataObject)
      {
        *ppvObject = static_cast<IDataObject *>(this);
        AddRef();
        return S_OK;
      }
      return E_NOINTERFACE;
    }

    ULONG __stdcall AddRef() override { return ++ref_count_; }

    ULONG __stdcall Release() override
    {
      const ULONG count = --ref_count_;
      if (count == 0)
        delete this;
      return count;
    }

    HRESULT __stdcall GetData(FORMATETC *pformatetcIn,
                              STGMEDIUM *pmedium) override
    {
      if (!pformatetcIn || !pmedium)
        return E_INVALIDARG;
      if ((pformatetcIn->tymed & TYMED_HGLOBAL) == 0)
        return DV_E_TYMED;

      if (pformatetcIn->cfFormat == static_cast<CLIPFORMAT>(g_cf_tab_payload))
      {
        const size_t len = payload_.size() + 1;
        HGLOBAL h = CopyBytesToHGlobal(payload_.c_str(), len);
        if (!h)
          return E_OUTOFMEMORY;
        pmedium->tymed = TYMED_HGLOBAL;
        pmedium->hGlobal = h;
        pmedium->pUnkForRelease = nullptr;
        return S_OK;
      }

      if (pformatetcIn->cfFormat ==
          static_cast<CLIPFORMAT>(g_cf_tab_source_pid))
      {
        DWORD pid = source_pid_;
        HGLOBAL h = CopyBytesToHGlobal(&pid, sizeof(pid));
        if (!h)
          return E_OUTOFMEMORY;
        pmedium->tymed = TYMED_HGLOBAL;
        pmedium->hGlobal = h;
        pmedium->pUnkForRelease = nullptr;
        return S_OK;
      }

      return DV_E_FORMATETC;
    }

    HRESULT __stdcall GetDataHere(FORMATETC *, STGMEDIUM *) override
    {
      return E_NOTIMPL;
    }

    HRESULT __stdcall QueryGetData(FORMATETC *pformatetc) override
    {
      if (!pformatetc)
        return E_INVALIDARG;
      if ((pformatetc->tymed & TYMED_HGLOBAL) == 0)
        return DV_E_TYMED;

      if (pformatetc->cfFormat == static_cast<CLIPFORMAT>(g_cf_tab_payload) ||
          pformatetc->cfFormat == static_cast<CLIPFORMAT>(g_cf_tab_source_pid))
      {
        return S_OK;
      }
      return DV_E_FORMATETC;
    }

    HRESULT __stdcall GetCanonicalFormatEtc(FORMATETC *, FORMATETC *) override
    {
      return E_NOTIMPL;
    }

    HRESULT __stdcall SetData(FORMATETC *, STGMEDIUM *, BOOL) override
    {
      return E_NOTIMPL;
    }

    HRESULT __stdcall EnumFormatEtc(DWORD, IEnumFORMATETC **) override
    {
      return E_NOTIMPL;
    }

    HRESULT __stdcall DAdvise(FORMATETC *, DWORD, IAdviseSink *, DWORD *) override
    {
      return OLE_E_ADVISENOTSUPPORTED;
    }

    HRESULT __stdcall DUnadvise(DWORD) override
    {
      return OLE_E_ADVISENOTSUPPORTED;
    }

    HRESULT __stdcall EnumDAdvise(IEnumSTATDATA **) override
    {
      return OLE_E_ADVISENOTSUPPORTED;
    }

  private:
    std::string payload_;
    DWORD source_pid_;
    ULONG ref_count_ = 1;
  };

  class FileDataObject : public IDataObject
  {
  public:
    explicit FileDataObject(std::vector<std::wstring> paths)
        : paths_(std::move(paths)), source_pid_(::GetCurrentProcessId()) {}

    HRESULT __stdcall QueryInterface(REFIID riid,
                                     void **ppvObject) override
    {
      if (!ppvObject)
        return E_POINTER;
      *ppvObject = nullptr;
      if (riid == IID_IUnknown || riid == IID_IDataObject)
      {
        *ppvObject = static_cast<IDataObject *>(this);
        AddRef();
        return S_OK;
      }
      return E_NOINTERFACE;
    }

    ULONG __stdcall AddRef() override { return ++ref_count_; }

    ULONG __stdcall Release() override
    {
      const ULONG count = --ref_count_;
      if (count == 0)
        delete this;
      return count;
    }

    HRESULT __stdcall GetData(FORMATETC *pformatetcIn,
                              STGMEDIUM *pmedium) override
    {
      if (!pformatetcIn || !pmedium)
        return E_INVALIDARG;
      if ((pformatetcIn->tymed & TYMED_HGLOBAL) == 0)
        return DV_E_TYMED;

      if (pformatetcIn->cfFormat == CF_HDROP)
      {
        HGLOBAL h = CreateDropFilesHGlobal(paths_);
        if (!h)
          return E_OUTOFMEMORY;
        pmedium->tymed = TYMED_HGLOBAL;
        pmedium->hGlobal = h;
        pmedium->pUnkForRelease = nullptr;
        return S_OK;
      }

      if (pformatetcIn->cfFormat ==
          static_cast<CLIPFORMAT>(g_cf_preferred_drop_effect))
      {
        DWORD effect = DROPEFFECT_MOVE;
        HGLOBAL h = CopyBytesToHGlobal(&effect, sizeof(effect));
        if (!h)
          return E_OUTOFMEMORY;
        pmedium->tymed = TYMED_HGLOBAL;
        pmedium->hGlobal = h;
        pmedium->pUnkForRelease = nullptr;
        return S_OK;
      }

      if (pformatetcIn->cfFormat ==
          static_cast<CLIPFORMAT>(g_cf_tab_source_pid))
      {
        DWORD pid = source_pid_;
        HGLOBAL h = CopyBytesToHGlobal(&pid, sizeof(pid));
        if (!h)
          return E_OUTOFMEMORY;
        pmedium->tymed = TYMED_HGLOBAL;
        pmedium->hGlobal = h;
        pmedium->pUnkForRelease = nullptr;
        return S_OK;
      }

      return DV_E_FORMATETC;
    }

    HRESULT __stdcall GetDataHere(FORMATETC *, STGMEDIUM *) override
    {
      return E_NOTIMPL;
    }

    HRESULT __stdcall QueryGetData(FORMATETC *pformatetc) override
    {
      if (!pformatetc)
        return E_INVALIDARG;
      if ((pformatetc->tymed & TYMED_HGLOBAL) == 0)
        return DV_E_TYMED;

      if (pformatetc->cfFormat == CF_HDROP ||
          pformatetc->cfFormat ==
              static_cast<CLIPFORMAT>(g_cf_preferred_drop_effect) ||
          pformatetc->cfFormat == static_cast<CLIPFORMAT>(g_cf_tab_source_pid))
      {
        return S_OK;
      }
      return DV_E_FORMATETC;
    }

    HRESULT __stdcall GetCanonicalFormatEtc(FORMATETC *, FORMATETC *) override
    {
      return E_NOTIMPL;
    }

    HRESULT __stdcall SetData(FORMATETC *, STGMEDIUM *, BOOL) override
    {
      return E_NOTIMPL;
    }

    HRESULT __stdcall EnumFormatEtc(DWORD, IEnumFORMATETC **) override
    {
      return E_NOTIMPL;
    }

    HRESULT __stdcall DAdvise(FORMATETC *, DWORD, IAdviseSink *, DWORD *) override
    {
      return OLE_E_ADVISENOTSUPPORTED;
    }

    HRESULT __stdcall DUnadvise(DWORD) override
    {
      return OLE_E_ADVISENOTSUPPORTED;
    }

    HRESULT __stdcall EnumDAdvise(IEnumSTATDATA **) override
    {
      return OLE_E_ADVISENOTSUPPORTED;
    }

  private:
    std::vector<std::wstring> paths_;
    DWORD source_pid_;
    ULONG ref_count_ = 1;
  };

  class TabDropSource : public IDropSource
  {
  public:
    HRESULT __stdcall QueryInterface(REFIID riid,
                                     void **ppvObject) override
    {
      if (!ppvObject)
        return E_POINTER;
      *ppvObject = nullptr;
      if (riid == IID_IUnknown || riid == IID_IDropSource)
      {
        *ppvObject = static_cast<IDropSource *>(this);
        AddRef();
        return S_OK;
      }
      return E_NOINTERFACE;
    }

    ULONG __stdcall AddRef() override { return ++ref_count_; }

    ULONG __stdcall Release() override
    {
      const ULONG count = --ref_count_;
      if (count == 0)
        delete this;
      return count;
    }

    HRESULT __stdcall QueryContinueDrag(BOOL fEscapePressed,
                                        DWORD grfKeyState) override
    {
      if (fEscapePressed)
      {
        canceled_by_escape_ = true;
        return DRAGDROP_S_CANCEL;
      }
      if ((grfKeyState & MK_LBUTTON) == 0)
      {
        dropped_by_mouse_release_ = true;
        return DRAGDROP_S_DROP;
      }
      return S_OK;
    }

    HRESULT __stdcall GiveFeedback(DWORD) override
    {
      return DRAGDROP_S_USEDEFAULTCURSORS;
    }

    bool dropped_by_mouse_release() const
    {
      return dropped_by_mouse_release_;
    }

    bool canceled_by_escape() const
    {
      return canceled_by_escape_;
    }

  private:
    ULONG ref_count_ = 1;
    bool dropped_by_mouse_release_ = false;
    bool canceled_by_escape_ = false;
  };

  class TabDropTarget : public IDropTarget
  {
  public:
    enum class DropKind
    {
      none,
      tab,
      file,
    };

    explicit TabDropTarget(
        flutter::MethodChannel<flutter::EncodableValue> *channel)
        : channel_(channel), pid_(::GetCurrentProcessId()) {}

    HRESULT __stdcall QueryInterface(REFIID riid,
                                     void **ppvObject) override
    {
      if (!ppvObject)
        return E_POINTER;
      *ppvObject = nullptr;
      if (riid == IID_IUnknown || riid == IID_IDropTarget)
      {
        *ppvObject = static_cast<IDropTarget *>(this);
        AddRef();
        return S_OK;
      }
      return E_NOINTERFACE;
    }

    ULONG __stdcall AddRef() override { return ++ref_count_; }

    ULONG __stdcall Release() override
    {
      const ULONG count = --ref_count_;
      if (count == 0)
        delete this;
      return count;
    }

    HRESULT __stdcall DragEnter(IDataObject *pDataObj, DWORD, POINTL,
                                DWORD *pdwEffect) override
    {
      if (!pdwEffect)
        return E_INVALIDARG;
      allow_drop_ = false;
      drop_kind_ = GetDropKind(pDataObj);
      if (drop_kind_ == DropKind::none)
      {
        NotifyHover(false);
        *pdwEffect = DROPEFFECT_NONE;
        return S_OK;
      }

      DWORD source_pid = 0;
      if (drop_kind_ == DropKind::tab &&
          GetSourcePid(pDataObj, &source_pid) && source_pid == pid_)
      {
        NotifyHover(false);
        *pdwEffect = DROPEFFECT_NONE;
        return S_OK;
      }

      allow_drop_ = true;
      NotifyHover(drop_kind_ == DropKind::tab);
      *pdwEffect = DROPEFFECT_MOVE;
      return S_OK;
    }

    HRESULT __stdcall DragOver(DWORD, POINTL, DWORD *pdwEffect) override
    {
      if (!pdwEffect)
        return E_INVALIDARG;
      *pdwEffect = allow_drop_ ? DROPEFFECT_MOVE : DROPEFFECT_NONE;
      return S_OK;
    }

    HRESULT __stdcall DragLeave() override
    {
      NotifyHover(false);
      drop_kind_ = DropKind::none;
      allow_drop_ = false;
      return S_OK;
    }

    HRESULT __stdcall Drop(IDataObject *pDataObj, DWORD, POINTL pt,
                           DWORD *pdwEffect) override
    {
      if (!pdwEffect)
        return E_INVALIDARG;
      NotifyHover(false);

      DropKind kind = drop_kind_;
      if (kind == DropKind::none)
        kind = GetDropKind(pDataObj);

      if (kind == DropKind::file)
      {
        std::vector<std::wstring> paths;
        if (!GetFilePaths(pDataObj, &paths) || paths.empty())
        {
          *pdwEffect = DROPEFFECT_NONE;
          return S_OK;
        }

        if (channel_)
        {
          flutter::EncodableList encoded_paths;
          encoded_paths.reserve(paths.size());
          for (const auto &path : paths)
            encoded_paths.emplace_back(WideToUtf8(path));

          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("paths")] =
              flutter::EncodableValue(encoded_paths);
          payload[flutter::EncodableValue("globalX")] =
              flutter::EncodableValue(static_cast<double>(pt.x));
          payload[flutter::EncodableValue("globalY")] =
              flutter::EncodableValue(static_cast<double>(pt.y));
          payload[flutter::EncodableValue("effect")] =
              flutter::EncodableValue("move");

          channel_->InvokeMethod(
              "onNativeFileDrop",
              std::make_unique<flutter::EncodableValue>(payload));
        }

        *pdwEffect = DROPEFFECT_MOVE;
        drop_kind_ = DropKind::none;
        allow_drop_ = false;
        return S_OK;
      }

      if (kind != DropKind::tab)
      {
        *pdwEffect = DROPEFFECT_NONE;
        return S_OK;
      }

      DWORD source_pid = 0;
      if (!GetSourcePid(pDataObj, &source_pid))
      {
        *pdwEffect = DROPEFFECT_NONE;
        return S_OK;
      }

      // Ignore tab drops originating from this process to avoid accidental
      // duplicates when users click-drag and release within the same window.
      if (source_pid == pid_)
      {
        *pdwEffect = DROPEFFECT_NONE;
        return S_OK;
      }

      std::string payload;
      if (!GetPayload(pDataObj, &payload) || payload.empty())
      {
        *pdwEffect = DROPEFFECT_NONE;
        return S_OK;
      }

      if (channel_)
      {
        channel_->InvokeMethod(
            "onNativeTabDrop",
            std::make_unique<flutter::EncodableValue>(payload));
      }

      *pdwEffect = DROPEFFECT_MOVE;
      drop_kind_ = DropKind::none;
      allow_drop_ = false;
      return S_OK;
    }

  private:
    DropKind GetDropKind(IDataObject *data)
    {
      if (HasTabPayload(data))
        return DropKind::tab;
      if (HasFileDrop(data))
        return DropKind::file;
      return DropKind::none;
    }

    bool HasTabPayload(IDataObject *data)
    {
      if (!data)
        return false;
      FORMATETC fmt = {static_cast<CLIPFORMAT>(g_cf_tab_payload), nullptr,
                       DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
      return data->QueryGetData(&fmt) == S_OK;
    }

    bool HasFileDrop(IDataObject *data)
    {
      if (!data)
        return false;
      FORMATETC fmt = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1,
                       TYMED_HGLOBAL};
      return data->QueryGetData(&fmt) == S_OK;
    }

    bool GetSourcePid(IDataObject *data, DWORD *out_pid)
    {
      if (!data || !out_pid)
        return false;
      FORMATETC fmt = {static_cast<CLIPFORMAT>(g_cf_tab_source_pid), nullptr,
                       DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
      STGMEDIUM medium{};
      if (data->GetData(&fmt, &medium) != S_OK)
        return false;

      bool ok = false;
      if (medium.tymed == TYMED_HGLOBAL && medium.hGlobal)
      {
        void *p = ::GlobalLock(medium.hGlobal);
        if (p && ::GlobalSize(medium.hGlobal) >= sizeof(DWORD))
        {
          *out_pid = *reinterpret_cast<DWORD *>(p);
          ok = true;
        }
        if (p)
          ::GlobalUnlock(medium.hGlobal);
      }
      ::ReleaseStgMedium(&medium);
      return ok;
    }

    bool GetFilePaths(IDataObject *data, std::vector<std::wstring> *out_paths)
    {
      if (!data || !out_paths)
        return false;
      FORMATETC fmt = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1,
                       TYMED_HGLOBAL};
      STGMEDIUM medium{};
      if (data->GetData(&fmt, &medium) != S_OK)
        return false;

      bool ok = false;
      if (medium.tymed == TYMED_HGLOBAL && medium.hGlobal)
      {
        HDROP drop = static_cast<HDROP>(medium.hGlobal);
        const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
        for (UINT i = 0; i < count; ++i)
        {
          const UINT len = ::DragQueryFileW(drop, i, nullptr, 0);
          if (len == 0)
            continue;
          std::wstring path(static_cast<size_t>(len) + 1, L'\0');
          ::DragQueryFileW(drop, i, path.data(), len + 1);
          path.resize(len);
          out_paths->push_back(std::move(path));
        }
        ok = !out_paths->empty();
      }
      ::ReleaseStgMedium(&medium);
      return ok;
    }

    bool GetPayload(IDataObject *data, std::string *out_payload)
    {
      if (!data || !out_payload)
        return false;
      FORMATETC fmt = {static_cast<CLIPFORMAT>(g_cf_tab_payload), nullptr,
                       DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
      STGMEDIUM medium{};
      if (data->GetData(&fmt, &medium) != S_OK)
        return false;

      bool ok = false;
      if (medium.tymed == TYMED_HGLOBAL && medium.hGlobal)
      {
        const SIZE_T size = ::GlobalSize(medium.hGlobal);
        void *p = ::GlobalLock(medium.hGlobal);
        if (p && size > 0)
        {
          const char *c = reinterpret_cast<const char *>(p);
          std::string s(c, c + size);
          while (!s.empty() && s.back() == '\0')
            s.pop_back();
          *out_payload = std::move(s);
          ok = true;
        }
        if (p)
          ::GlobalUnlock(medium.hGlobal);
      }
      ::ReleaseStgMedium(&medium);
      return ok;
    }

    void NotifyHover(bool is_hovering)
    {
      if (hover_notified_ == is_hovering)
        return;
      hover_notified_ = is_hovering;
      if (!channel_)
        return;
      channel_->InvokeMethod(
          "onNativeTabDragHover",
          std::make_unique<flutter::EncodableValue>(is_hovering));
    }

    flutter::MethodChannel<flutter::EncodableValue> *channel_;
    DWORD pid_;
    ULONG ref_count_ = 1;
    bool allow_drop_ = false;
    bool hover_notified_ = false;
    DropKind drop_kind_ = DropKind::none;
  };

} // namespace

// static
void WindowUtilsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar)
{
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "cb_file_manager/window_utils",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<WindowUtilsPlugin>(registrar);

  plugin->channel_ = std::move(channel);
  plugin->EnsureDropTargetRegistered();
  plugin->EnsureWindowProcDelegateRegistered();

  plugin->channel_->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result)
      {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

WindowUtilsPlugin::WindowUtilsPlugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {}

WindowUtilsPlugin::~WindowUtilsPlugin()
{
  if (window_proc_delegate_id_ >= 0 && registrar_)
  {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
    window_proc_delegate_id_ = -1;
  }
  if (drop_target_hwnd_)
  {
    ::RevokeDragDrop(drop_target_hwnd_);
    drop_target_hwnd_ = nullptr;
  }
  if (drop_target_)
  {
    drop_target_->Release();
    drop_target_ = nullptr;
  }
}

void WindowUtilsPlugin::EnsureDropTargetRegistered()
{
  if (drop_target_)
    return;
  if (!registrar_)
    return;

  if (!g_ole_initialized)
  {
    const HRESULT hr = ::OleInitialize(nullptr);
    g_ole_initialized = (hr == S_OK || hr == S_FALSE);
  }

  if (g_cf_tab_payload == 0)
  {
    g_cf_tab_payload =
        ::RegisterClipboardFormatW(L"CB_FILE_MANAGER_TAB_PAYLOAD_JSON");
  }
  if (g_cf_tab_source_pid == 0)
  {
    g_cf_tab_source_pid =
        ::RegisterClipboardFormatW(L"CB_FILE_MANAGER_TAB_SOURCE_PID");
  }
  if (g_cf_preferred_drop_effect == 0)
  {
    g_cf_preferred_drop_effect =
        ::RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT);
  }

  HWND hwnd = GetTopLevelWindow(registrar_);
  if (!hwnd)
    return;

  drop_target_hwnd_ = hwnd;
  drop_target_ = new TabDropTarget(channel_.get());

  const HRESULT hr = ::RegisterDragDrop(hwnd, drop_target_);
  if (hr == DRAGDROP_E_ALREADYREGISTERED)
  {
    drop_target_->Release();
    drop_target_ = nullptr;
    drop_target_hwnd_ = nullptr;
    return;
  }
  if (FAILED(hr))
  {
    drop_target_->Release();
    drop_target_ = nullptr;
    drop_target_hwnd_ = nullptr;
  }
}

void WindowUtilsPlugin::EnsureWindowProcDelegateRegistered()
{
  if (!registrar_ || window_proc_delegate_id_ >= 0)
    return;

  window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      // Capture `this` so each plugin instance tracks its OWN window's
      // backdrop state. Using shared anonymous-namespace globals caused
      // cross-window pollution: a secondary window (e.g. progress/PiP)
      // calling setWindowsSystemBackdrop(enabled:false) would set the
      // global to false, making the main window's delegate skip re-apply.
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
          -> std::optional<LRESULT>
      {
        if (!this->backdrop_active_)
          return std::nullopt;

        switch (message)
        {
        case WM_ACTIVATE:
          // Re-apply the transparent-gradient accent when the window becomes
          // active. Windows resets WCA_ACCENT_POLICY on every WM_ACTIVATE.
          if (LOWORD(wparam) != WA_INACTIVE)
          {
            HWND root = ::GetAncestor(hwnd, GA_ROOT);
            HWND target = root ? root : hwnd;
            if (this->backdrop_prefer_acrylic_)
            {
              ScheduleBackdropReapplyForPluginInstance(
                  this->registrar_, target, this->backdrop_active_,
                  this->backdrop_prefer_acrylic_, this->backdrop_dark_mode_);
            }
            else
            {
              ScheduleBackdropReapplyForPluginInstance(
                  this->registrar_, target, this->backdrop_active_,
                  this->backdrop_prefer_acrylic_, this->backdrop_dark_mode_);
            }
          }
          break;

        case WM_NCACTIVATE:
          // Non-client area activation also triggers a DWM accent reset.
          if (wparam != FALSE)
          {
            HWND root = ::GetAncestor(hwnd, GA_ROOT);
            HWND target = root ? root : hwnd;
            if (this->backdrop_prefer_acrylic_)
            {
              ScheduleBackdropReapplyForPluginInstance(
                  this->registrar_, target, this->backdrop_active_,
                  this->backdrop_prefer_acrylic_, this->backdrop_dark_mode_);
            }
            else
            {
              ScheduleBackdropReapplyForPluginInstance(
                  this->registrar_, target, this->backdrop_active_,
                  this->backdrop_prefer_acrylic_, this->backdrop_dark_mode_);
            }
          }
          break;

        case WM_SIZE:
          if (wparam == SIZE_RESTORED || wparam == SIZE_MAXIMIZED)
          {
            ScheduleBackdropReapplyForPluginInstance(
                this->registrar_, hwnd, this->backdrop_active_,
                this->backdrop_prefer_acrylic_, this->backdrop_dark_mode_);
          }
          break;

        case WM_EXITSIZEMOVE:
        case WM_SHOWWINDOW:
          ScheduleBackdropReapplyForPluginInstance(
              this->registrar_, hwnd, this->backdrop_active_,
              this->backdrop_prefer_acrylic_, this->backdrop_dark_mode_);
          break;

        case WM_TIMER:
          if (wparam == 0xCBA1 || wparam == 0xCBA2 || wparam == 0xCBA3)
          {
            ::KillTimer(hwnd, static_cast<UINT_PTR>(wparam));
            ReapplyBackdropForPluginInstance(
                this->registrar_, hwnd, this->backdrop_active_,
                this->backdrop_prefer_acrylic_, this->backdrop_dark_mode_);
          }
          break;

        case WM_THEMECHANGED:
        case WM_DWMCOMPOSITIONCHANGED:
        {
          // Full re-apply on DWM composition/theme change events.
          ScheduleBackdropReapplyForPluginInstance(
              this->registrar_, hwnd, this->backdrop_active_,
              this->backdrop_prefer_acrylic_, this->backdrop_dark_mode_);
          break;
        }
        }
        // Never consume the message — let Flutter and DefWindowProc handle it.
        return std::nullopt;
      });
}

void WindowUtilsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
  const auto method = method_call.method_name();

  if (method == "allowForegroundWindow")
  {
    // Allows this app (or a spawned child) to move itself to the foreground.
    // Use with care: Windows may still apply focus-stealing prevention.
    DWORD target = static_cast<DWORD>(-1); // ASFW_ANY

    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args)
    {
      auto it_any = args->find(flutter::EncodableValue("any"));
      if (it_any != args->end())
      {
        if (const auto *any = std::get_if<bool>(&it_any->second))
        {
          if (!*any)
          {
            target = 0;
          }
        }
      }

      auto it_pid = args->find(flutter::EncodableValue("pid"));
      if (it_pid != args->end())
      {
        if (const auto *pid = std::get_if<int>(&it_pid->second))
        {
          if (*pid > 0)
          {
            target = static_cast<DWORD>(*pid);
          }
        }
      }
    }
    else if (const auto *any_bool =
                 std::get_if<bool>(method_call.arguments()))
    {
      if (!*any_bool)
      {
        target = 0;
      }
    }

    const BOOL ok = ::AllowSetForegroundWindow(target);
    result->Success(flutter::EncodableValue(ok != FALSE));
    return;
  }

  if (method == "forceActivateWindow")
  {
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!hwnd)
    {
      result->Error("NO_WINDOW", "Top-level window handle not available.");
      return;
    }

    // Restore if minimized, then try multiple activation paths.
    ::ShowWindow(hwnd, SW_RESTORE);
    ::SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    ::BringWindowToTop(hwnd);
    ::SetActiveWindow(hwnd);

    const BOOL ok = ::SetForegroundWindow(hwnd);
    result->Success(flutter::EncodableValue(ok != FALSE));
    return;
  }

  if (method == "startWindowDragIfMouseDown")
  {
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!hwnd)
    {
      result->Error("NO_WINDOW", "Top-level window handle not available.");
      return;
    }

    if ((::GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0)
    {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    bool expected = false;
    if (!g_tab_window_drag_active.compare_exchange_strong(expected, true))
    {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    POINT cursor{};
    RECT window_rect{};
    if (!::GetCursorPos(&cursor) || !::GetWindowRect(hwnd, &window_rect))
    {
      g_tab_window_drag_active.store(false);
      result->Success(flutter::EncodableValue(false));
      return;
    }

    const LONG pointer_offset_x = cursor.x - window_rect.left;
    const LONG pointer_offset_y = cursor.y - window_rect.top;

    std::thread([hwnd, pointer_offset_x, pointer_offset_y]()
                {
      while (::IsWindow(hwnd) &&
             ((::GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0))
      {
        POINT current_cursor{};
        if (::GetCursorPos(&current_cursor))
        {
          ::SetWindowPos(
              hwnd,
              nullptr,
              current_cursor.x - pointer_offset_x,
              current_cursor.y - pointer_offset_y,
              0,
              0,
              SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
        ::Sleep(kTabWindowDragPollIntervalMs);
      }
      g_tab_window_drag_active.store(false); })
        .detach();

    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "startNativeTabDrag")
  {
    EnsureDropTargetRegistered();

    const auto *payload =
        std::get_if<std::string>(method_call.arguments());
    if (!payload || payload->empty())
    {
      result->Error("INVALID_ARGUMENTS", "Missing payload.");
      return;
    }

    if (!g_ole_initialized || g_cf_tab_payload == 0 || g_cf_tab_source_pid == 0)
    {
      result->Error("OLE_NOT_INITIALIZED", "OLE drag-drop is not available.");
      return;
    }

    IDataObject *data_object = new TabDataObject(*payload);
    TabDropSource *drop_source = new TabDropSource();
    DWORD effect = DROPEFFECT_NONE;
    const HRESULT hr = ::DoDragDrop(data_object, drop_source, DROPEFFECT_MOVE,
                                    &effect);

    const bool moved = (hr == DRAGDROP_S_DROP) && ((effect & DROPEFFECT_MOVE) != 0);
    bool detached = false;
    if (!moved && drop_source->dropped_by_mouse_release() &&
        !drop_source->canceled_by_escape())
    {
      POINT cursor{};
      HWND source_window = GetTopLevelWindow(registrar_);
      if (::GetCursorPos(&cursor) && source_window)
      {
        HWND window_at_cursor = ::WindowFromPoint(cursor);
        HWND root_window =
            window_at_cursor ? ::GetAncestor(window_at_cursor, GA_ROOT) : nullptr;
        detached = root_window != source_window;
      }
    }

    drop_source->Release();
    data_object->Release();

    const char *drag_result =
        moved ? "moved" : (detached ? "detached" : "canceled");
    result->Success(flutter::EncodableValue(drag_result));
    return;
  }

  if (method == "startNativeFileDrag")
  {
    EnsureDropTargetRegistered();

    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments)
    {
      result->Error("INVALID_ARGUMENTS", "Missing arguments.");
      return;
    }

    const auto paths_it = arguments->find(flutter::EncodableValue("paths"));
    if (paths_it == arguments->end())
    {
      result->Error("INVALID_ARGUMENTS", "Missing paths.");
      return;
    }

    const auto *encoded_paths =
        std::get_if<flutter::EncodableList>(&paths_it->second);
    if (!encoded_paths)
    {
      result->Error("INVALID_ARGUMENTS", "Paths must be a list.");
      return;
    }

    std::vector<std::wstring> paths;
    for (const auto &value : *encoded_paths)
    {
      if (const auto *path = std::get_if<std::string>(&value))
      {
        std::wstring wide_path = Utf8ToWide(*path);
        if (!wide_path.empty())
          paths.push_back(std::move(wide_path));
      }
    }

    if (paths.empty())
    {
      result->Error("INVALID_ARGUMENTS", "No valid paths.");
      return;
    }

    if (!g_ole_initialized || g_cf_tab_source_pid == 0 ||
        g_cf_preferred_drop_effect == 0)
    {
      result->Error("OLE_NOT_INITIALIZED", "OLE drag-drop is not available.");
      return;
    }

    IDataObject *data_object = new FileDataObject(std::move(paths));
    IDropSource *drop_source = new TabDropSource();
    DWORD effect = DROPEFFECT_NONE;
    const HRESULT hr = ::DoDragDrop(data_object, drop_source, DROPEFFECT_MOVE,
                                    &effect);
    drop_source->Release();
    data_object->Release();

    const bool moved = (hr == DRAGDROP_S_DROP) && ((effect & DROPEFFECT_MOVE) != 0);
    result->Success(flutter::EncodableValue(moved ? "moved" : "canceled"));
    return;
  }

  if (method == "setNativeFullScreen")
  {
    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments)
    {
      result->Error("INVALID_ARGUMENTS", "Missing arguments.");
      return;
    }

    const auto it =
        arguments->find(flutter::EncodableValue("isFullScreen"));
    if (it == arguments->end())
    {
      result->Error("INVALID_ARGUMENTS", "Missing isFullScreen.");
      return;
    }

    const bool is_fullscreen = std::get<bool>(it->second);
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!hwnd)
    {
      result->Error("NO_WINDOW", "Main window handle not available.");
      return;
    }

    if (is_fullscreen)
    {
      EnterFullscreen(hwnd);
    }
    else
    {
      ExitFullscreen(hwnd);
    }

    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "isNativeFullScreen")
  {
    result->Success(flutter::EncodableValue(g_is_fullscreen));
    return;
  }

  if (method == "setNativeCaptionVisible")
  {
    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments)
    {
      result->Error("INVALID_ARGUMENTS", "Missing arguments.");
      return;
    }

    const auto it = arguments->find(flutter::EncodableValue("visible"));
    if (it == arguments->end())
    {
      result->Error("INVALID_ARGUMENTS", "Missing visible.");
      return;
    }

    const bool visible = std::get<bool>(it->second);
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!hwnd)
    {
      result->Error("NO_WINDOW", "Top-level window handle not available.");
      return;
    }

    LONG_PTR style = ::GetWindowLongPtr(hwnd, GWL_STYLE);
    if (visible)
    {
      style |= WS_CAPTION;
    }
    else
    {
      style &= ~WS_CAPTION;
    }

    ::SetWindowLongPtr(hwnd, GWL_STYLE, style);
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_FRAMECHANGED);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "setNativeSystemMenuVisible")
  {
    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments)
    {
      result->Error("INVALID_ARGUMENTS", "Missing arguments.");
      return;
    }

    const auto it = arguments->find(flutter::EncodableValue("visible"));
    if (it == arguments->end())
    {
      result->Error("INVALID_ARGUMENTS", "Missing visible.");
      return;
    }

    const bool visible = std::get<bool>(it->second);
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!hwnd)
    {
      result->Error("NO_WINDOW", "Top-level window handle not available.");
      return;
    }

    LONG_PTR style = ::GetWindowLongPtr(hwnd, GWL_STYLE);

    if (visible)
    {
      // Restore the default system menu and all caption styles.
      ::GetSystemMenu(hwnd, TRUE); // TRUE resets to default
      style |= (WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
      ::SetWindowLongPtr(hwnd, GWL_STYLE, style);
    }
    else
    {
      // Remove WS_SYSMENU to stop the DWM from rendering native caption
      // buttons (close / minimize / maximize).  Keep WS_MINIMIZEBOX and
      // WS_MAXIMIZEBOX: the Windows Shell still recognises these flags
      // for taskbar-button minimize when combined with correct
      // WM_ACTIVATE handling (see win32_window.cpp — we no longer call
      // SetFocus during WA_INACTIVE which was the actual root cause of
      // "taskbar click won't minimize").
      style &= ~WS_SYSMENU;
      style |= (WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
      ::SetWindowLongPtr(hwnd, GWL_STYLE, style);
    }

    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_FRAMECHANGED);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "setWindowsSystemBackdrop")
  {
    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments)
    {
      result->Error("INVALID_ARGUMENTS", "Missing arguments.");
      return;
    }

    bool enabled = false;
    bool prefer_acrylic = true;
    bool is_dark_mode = false;

    const auto enabled_it = arguments->find(flutter::EncodableValue("enabled"));
    if (enabled_it != arguments->end())
    {
      if (const auto *value = std::get_if<bool>(&enabled_it->second))
      {
        enabled = *value;
      }
    }

    const auto acrylic_it =
        arguments->find(flutter::EncodableValue("preferAcrylic"));
    if (acrylic_it != arguments->end())
    {
      if (const auto *value = std::get_if<bool>(&acrylic_it->second))
      {
        prefer_acrylic = *value;
      }
    }

    const auto dark_mode_it =
        arguments->find(flutter::EncodableValue("isDarkMode"));
    if (dark_mode_it != arguments->end())
    {
      if (const auto *value = std::get_if<bool>(&dark_mode_it->second))
      {
        is_dark_mode = *value;
      }
    }

    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!hwnd)
    {
      result->Error("NO_WINDOW", "Top-level window handle not available.");
      return;
    }

    HWND flutter_view_hwnd = GetMainWindow(registrar_);
    const RTL_OSVERSIONINFOW version = GetWindowsVersionInfo();
    const bool ok =
        SetNativeSystemBackdrop(hwnd, enabled, prefer_acrylic, is_dark_mode);
    if (flutter_view_hwnd && flutter_view_hwnd != hwnd)
    {
      SetFlutterChildBackdropTransparency(
          flutter_view_hwnd, version.dwBuildNumber, enabled && prefer_acrylic);
    }
    // Keep per-instance state in sync so the window proc delegate uses the
    // correct values for THIS window, not a shared/polluted global.
    backdrop_active_ = enabled;
    backdrop_prefer_acrylic_ = prefer_acrylic;
    backdrop_dark_mode_ = is_dark_mode;
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "fitWindowToWorkArea")
  {
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!hwnd)
    {
      result->Error("NO_WINDOW", "Top-level window handle not available.");
      return;
    }

    const RECT work_rect = GetCurrentMonitorWorkRect(hwnd);
    if (work_rect.right <= work_rect.left || work_rect.bottom <= work_rect.top)
    {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    ::SetWindowPos(hwnd, nullptr, work_rect.left, work_rect.top,
                   work_rect.right - work_rect.left,
                   work_rect.bottom - work_rect.top,
                   SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  result->NotImplemented();
}
