#include "window_utils_plugin.h"
#include "window_backdrop.h"
#include "torrent_launch.h"
#include "resource.h"
#include "engine_window_host.h"

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
#include <climits>
#include <cstring>
#include <atomic>
#include <thread>
#include <mutex>
#include <cmath>
#include <algorithm>
#include <map>

namespace
{
  constexpr UINT kTorrentNotificationMessage = WM_APP + 0x43;
  constexpr UINT kTorrentNotificationIcon = 0xCBF1;
  constexpr UINT_PTR kTorrentNotificationTimer = 0xCBA4;

  struct FullscreenState {
    bool active = false;
    RECT frame{};
    LONG_PTR style = 0;
    bool maximized = false;
  };
  std::map<HWND, FullscreenState> fullscreen_states;
  constexpr wchar_t kRevealHoldProp[] = L"CBFileHub.RevealHold";
  constexpr wchar_t kMergedProp[] = L"CBFileHub.Merged";
  bool RevealHeld(HWND hwnd) { return ::GetPropW(hwnd, kRevealHoldProp) != nullptr; }
  void SetRevealHeld(HWND hwnd, bool held) {
    if (held) ::SetPropW(hwnd, kRevealHoldProp, reinterpret_cast<HANDLE>(1));
    else ::RemovePropW(hwnd, kRevealHoldProp);
  }
  static bool g_ole_initialized = false;
  static UINT g_cf_tab_payload = 0;
  static UINT g_cf_tab_source_pid = 0;
  static HWND g_tab_source_window = nullptr;
  static UINT g_cf_preferred_drop_effect = 0;
  // One mouse, one drag: excludes a second tab or window drag in any window.
  static std::atomic<bool> g_tab_window_drag_active{false};
  // Set on a window while its own drag loop moves it. Every window shares this
  // process, so releasing a reveal hold must not wait for another window's drag.
  constexpr wchar_t kWindowDraggingProp[] = L"CBFileHub.WindowDragging";

  // All windows share the platform thread, so they are no longer kept from
  // taking the foreground from each other. A window the tabs just left can
  // request focus for its view (Flutter's ::SetFocus), which activates it and
  // raises it over the window that received the tabs. For a moment after we
  // activate a window for the user, other windows yield to it.
  struct FocusHandoff
  {
    HWND window = nullptr;
    ULONGLONG until = 0;
  };
  FocusHandoff g_focus_handoff;
  constexpr ULONGLONG kFocusHandoffMs = 1000;
  constexpr UINT kFocusHandoffMessage = WM_APP + 0x46;

  constexpr DWORD kTabWindowDragPollIntervalMs = 8;
  // Cursor polling period of a tab-window drag, on a high-resolution timer.
  constexpr LONGLONG kTabWindowDragTickUs = 4000;

  // Tab merging. A tab shell publishes its tab strip in screen pixels as
  // properties of its top-level window. A window dragged by its tab reads them
  // to find a strip under the cursor without a round trip to that process,
  // then reports hover (posted, never blocking) and the drop (WM_COPYDATA).
  constexpr wchar_t kTabStripHostProp[] = L"CBFileHub.TabStrip.v1";
  constexpr wchar_t kTabStripLeftProp[] = L"CBFileHub.TabStrip.Left";
  constexpr wchar_t kTabStripTopProp[] = L"CBFileHub.TabStrip.Top";
  constexpr wchar_t kTabStripRightProp[] = L"CBFileHub.TabStrip.Right";
  constexpr wchar_t kTabStripBottomProp[] = L"CBFileHub.TabStrip.Bottom";
  constexpr ULONG_PTR kTabMergeEnter = 0x43425445; // "CBTE": label
  constexpr ULONG_PTR kTabMergeDrop = 0x43425444;  // "CBTD": tab payload
  constexpr WPARAM kTabMergeMove = 1;
  constexpr WPARAM kTabMergeLeave = 2;
  constexpr DWORD kTabMergeMaxBytes = 1024 * 1024;
  constexpr UINT kTabMergeEnterTimeoutMs = 50;
  constexpr UINT kTabMergeDropTimeoutMs = 1000;
  // A dragged window repeats its hover while the cursor rests; a target that
  // hears nothing for longer (the dragged process died) clears its indicator.
  constexpr ULONGLONG kTabMergeKeepAliveMs = 250;
  constexpr UINT kTabMergeHoverTimeoutMs = 800;
  constexpr UINT_PTR kTabMergeHoverTimer = 0xCBA5;
  constexpr UINT kTabWindowMergedMessage = WM_APP + 0x44;
  constexpr UINT kTabTearOffEndedMessage = WM_APP + 0x45;
  // How long a dropped tear-off preview waits for the real window.
  constexpr ULONGLONG kTearOffGhostHoldMs = 5000;
  constexpr wchar_t kTearOffGhostClass[] = L"CBFileHubTabTearOffGhost";
  constexpr DWORD kDwmwaCloak = 13;
  constexpr DWORD kDwmwaCloaked = 14;

  struct TabMergeHeader
  {
    LONG x; // Screen pixels.
    LONG y;
  };

  typedef LONG NTSTATUS, *PNTSTATUS;
  typedef NTSTATUS(WINAPI *RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);
#define STATUS_SUCCESS (0x00000000)

  bool SetNativeSystemBackdrop(
      WindowBackdrop::State &state, HWND hwnd, HWND view, bool enabled,
      bool prefer_acrylic, bool is_dark_mode);
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

  void ReapplyBackdropForPluginInstance(
      flutter::PluginRegistrarWindows *registrar,
      WindowBackdrop::State &state,
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
    if (!target || ::IsIconic(target) || !::IsWindowVisible(target))
      return;

    SetNativeSystemBackdrop(state, target, GetMainWindow(registrar), active,
                            prefer_acrylic, dark_mode);
  }

  void ScheduleBackdropReapplyForPluginInstance(
      HWND hwnd, bool active)
  {
    if (!active)
      return;

    // Wait until native layout/activation has finished before touching DWM.
    // Repeated size events coalesce instead of rebuilding the material inside
    // WM_SIZE while Flutter's surface is still changing.
    if (!hwnd || ::IsIconic(hwnd) || !::IsWindowVisible(hwnd)) return;
    ::SetTimer(hwnd, 0xCBA0, 16, nullptr);
    ::SetTimer(hwnd, 0xCBA1, 80, nullptr);
    ::SetTimer(hwnd, 0xCBA2, 240, nullptr);
    ::SetTimer(hwnd, 0xCBA3, 520, nullptr);
  }

  bool SetNativeSystemBackdrop(
      WindowBackdrop::State &state, HWND hwnd, HWND view, bool enabled,
      bool prefer_acrylic, bool is_dark_mode)
  {
    return WindowBackdrop::Sync(
        state, hwnd, view, GetWindowsVersionInfo().dwBuildNumber,
        enabled, prefer_acrylic, is_dark_mode);
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

    if (!fullscreen_states[hwnd].active)
    {
      fullscreen_states[hwnd].maximized = ::IsZoomed(hwnd);
      fullscreen_states[hwnd].style = ::GetWindowLongPtr(hwnd, GWL_STYLE);
      ::GetWindowRect(hwnd, &fullscreen_states[hwnd].frame);
    }

    fullscreen_states[hwnd].active = true;

    const RECT monitor_rect = GetCurrentMonitorRect(hwnd);

    ::SetWindowLongPtr(hwnd, GWL_STYLE,
                       fullscreen_states[hwnd].style & ~WS_OVERLAPPEDWINDOW);

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
    if (!fullscreen_states[hwnd].active)
      return;

    fullscreen_states[hwnd].active = false;

    ::SetWindowLongPtr(hwnd, GWL_STYLE, fullscreen_states[hwnd].style);

    // Refresh the frame.
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_FRAMECHANGED);

    if (fullscreen_states[hwnd].maximized)
    {
      ::PostMessage(hwnd, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
    }
    else
    {
      ::SetWindowPos(hwnd, nullptr, fullscreen_states[hwnd].frame.left,
                     fullscreen_states[hwnd].frame.top,
                     fullscreen_states[hwnd].frame.right -
                         fullscreen_states[hwnd].frame.left,
                     fullscreen_states[hwnd].frame.bottom -
                         fullscreen_states[hwnd].frame.top,
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
        flutter::MethodChannel<flutter::EncodableValue> *channel, HWND view_hwnd)
        : channel_(channel), view_hwnd_(view_hwnd), pid_(::GetCurrentProcessId()) {}

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
          GetSourcePid(pDataObj, &source_pid) && source_pid == pid_ &&
          ::GetAncestor(view_hwnd_, GA_ROOT) == g_tab_source_window)
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
          // OLE supplies physical screen pixels. Flutter hit testing uses
          // logical coordinates relative to the rendering view's client area.
          POINT client_point = {pt.x, pt.y};
          ::ScreenToClient(view_hwnd_, &client_point);
          const UINT dpi = ::GetDpiForWindow(view_hwnd_);
          const double scale = dpi == 0 ? 1.0 : dpi / 96.0;
          payload[flutter::EncodableValue("paths")] =
              flutter::EncodableValue(encoded_paths);
          payload[flutter::EncodableValue("globalX")] =
              flutter::EncodableValue(client_point.x / scale);
          payload[flutter::EncodableValue("globalY")] =
              flutter::EncodableValue(client_point.y / scale);
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

      // Ignore tab drops originating from this window to avoid accidental
      // duplicates when users click-drag and release within the same window.
      if (source_pid == pid_ && ::GetAncestor(view_hwnd_, GA_ROOT) == g_tab_source_window)
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
    HWND view_hwnd_;
    DWORD pid_;
    ULONG ref_count_ = 1;
    bool allow_drop_ = false;
    bool hover_notified_ = false;
    DropKind drop_kind_ = DropKind::none;
  };

  UINT TabMergeMessage()
  {
    static const UINT message =
        ::RegisterWindowMessageW(L"CBFileHub.TabMerge.v1");
    return message;
  }

  void SetLongProp(HWND hwnd, const wchar_t *name, LONG value)
  {
    ::SetPropW(hwnd, name,
               reinterpret_cast<HANDLE>(static_cast<INT_PTR>(value)));
  }

  LONG GetLongProp(HWND hwnd, const wchar_t *name)
  {
    return static_cast<LONG>(reinterpret_cast<INT_PTR>(::GetPropW(hwnd, name)));
  }

  bool IsWindowCloaked(HWND hwnd)
  {
    DWORD cloaked = 0;
    return SUCCEEDED(::DwmGetWindowAttribute(hwnd, kDwmwaCloaked, &cloaked,
                                             sizeof(cloaked))) &&
           cloaked != 0;
  }

  void SetWindowCloaked(HWND hwnd, bool cloaked)
  {
    BOOL value = cloaked ? TRUE : FALSE;
    ::DwmSetWindowAttribute(hwnd, kDwmwaCloak, &value, sizeof(value));
  }

  void BeginFocusHandoff(HWND hwnd)
  {
    g_focus_handoff = {hwnd, ::GetTickCount64() + kFocusHandoffMs};
  }

  // Whether [hwnd] must not take the foreground from the window just handed it.
  bool YieldsFocus(HWND hwnd)
  {
    const HWND to = g_focus_handoff.window;
    if (!to || to == hwnd || ::GetTickCount64() >= g_focus_handoff.until)
      return false;
    return ::IsWindow(to) && ::IsWindowVisible(to) && !::IsIconic(to) &&
           !IsWindowCloaked(to);
  }

  bool GetTabStripScreenRect(HWND hwnd, RECT *rect)
  {
    if (!::GetPropW(hwnd, kTabStripHostProp))
      return false;
    rect->left = GetLongProp(hwnd, kTabStripLeftProp);
    rect->top = GetLongProp(hwnd, kTabStripTopProp);
    rect->right = GetLongProp(hwnd, kTabStripRightProp);
    rect->bottom = GetLongProp(hwnd, kTabStripBottomProp);
    return rect->right > rect->left && rect->bottom > rect->top;
  }

  bool IsCandidateTopLevelWindow(HWND hwnd)
  {
    return ::IsWindowVisible(hwnd) && !::IsIconic(hwnd) &&
           (::GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TRANSPARENT) == 0;
  }

  struct TabStripHostSearch
  {
    POINT point;
    HWND exclude;
    HWND found;
  };

  BOOL CALLBACK FindTabStripHostProc(HWND hwnd, LPARAM lparam)
  {
    auto *search = reinterpret_cast<TabStripHostSearch *>(lparam);
    if (hwnd == search->exclude || !IsCandidateTopLevelWindow(hwnd))
      return TRUE;
    RECT rect{};
    if (!::GetWindowRect(hwnd, &rect) || !::PtInRect(&rect, search->point) ||
        IsWindowCloaked(hwnd))
      return TRUE;
    // EnumWindows walks the Z order from the top, so this is the window the
    // user sees under the cursor. Any other app's window there hides ours.
    RECT strip{};
    if (GetTabStripScreenRect(hwnd, &strip) &&
        ::PtInRect(&strip, search->point))
      search->found = hwnd;
    return FALSE;
  }

  // The tab shell whose tab strip is visible under [point], ignoring [exclude].
  HWND FindTabStripHostAt(POINT point, HWND exclude)
  {
    TabStripHostSearch search{point, exclude, nullptr};
    ::EnumWindows(FindTabStripHostProc, reinterpret_cast<LPARAM>(&search));
    return search.found;
  }

  BOOL CALLBACK FindOtherTabStripHostProc(HWND hwnd, LPARAM lparam)
  {
    auto *search = reinterpret_cast<TabStripHostSearch *>(lparam);
    if (hwnd == search->exclude || !::GetPropW(hwnd, kTabStripHostProp) ||
        !IsCandidateTopLevelWindow(hwnd) || IsWindowCloaked(hwnd))
      return TRUE;
    search->found = hwnd;
    return FALSE;
  }

  bool HasOtherTabStripHost(HWND exclude)
  {
    TabStripHostSearch search{{0, 0}, exclude, nullptr};
    ::EnumWindows(FindOtherTabStripHostProc, reinterpret_cast<LPARAM>(&search));
    return search.found != nullptr;
  }

  bool SendTabMergeData(HWND target, HWND source, ULONG_PTR kind, POINT point,
                        const std::string &text, UINT timeout_ms)
  {
    std::vector<char> buffer(sizeof(TabMergeHeader) + text.size());
    const TabMergeHeader header{point.x, point.y};
    memcpy(buffer.data(), &header, sizeof(header));
    if (!text.empty())
      memcpy(buffer.data() + sizeof(header), text.data(), text.size());
    COPYDATASTRUCT data{kind, static_cast<DWORD>(buffer.size()), buffer.data()};
    DWORD_PTR accepted = FALSE;
    const LRESULT sent = ::SendMessageTimeoutW(
        target, WM_COPYDATA, reinterpret_cast<WPARAM>(source),
        reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG | SMTO_NORMAL,
        timeout_ms, &accepted);
    return sent != 0 && accepted == TRUE;
  }

  void PostTabMergeHover(HWND target, WPARAM kind, POINT point)
  {
    ::PostMessageW(target, TabMergeMessage(), kind,
                   MAKELPARAM(static_cast<SHORT>(point.x),
                              static_cast<SHORT>(point.y)));
  }

#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

  // Sleep(8) really waits a full 15.6 ms scheduler tick unless something has
  // raised the timer resolution, which makes the window lag the cursor.
  class DragTicker
  {
  public:
    DragTicker()
        : timer_(::CreateWaitableTimerExW(
              nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
              TIMER_ALL_ACCESS)) {}
    ~DragTicker()
    {
      if (timer_)
        ::CloseHandle(timer_);
    }
    DragTicker(const DragTicker &) = delete;
    DragTicker &operator=(const DragTicker &) = delete;

    void Wait()
    {
      if (timer_)
      {
        LARGE_INTEGER due{};
        due.QuadPart = -kTabWindowDragTickUs * 10;
        if (::SetWaitableTimer(timer_, &due, 0, nullptr, nullptr, FALSE) &&
            ::WaitForSingleObject(timer_, 100) == WAIT_OBJECT_0)
          return;
      }
      ::Sleep(kTabWindowDragPollIntervalMs);
    }

    // Like Wait, but also dispatches this thread's window messages.
    void WaitPumping()
    {
      bool armed = false;
      if (timer_)
      {
        LARGE_INTEGER due{};
        due.QuadPart = -kTabWindowDragTickUs * 10;
        armed = ::SetWaitableTimer(timer_, &due, 0, nullptr, nullptr, FALSE);
      }
      ::MsgWaitForMultipleObjects(armed ? 1 : 0, armed ? &timer_ : nullptr,
                                  FALSE,
                                  armed ? 100 : kTabWindowDragPollIntervalMs,
                                  QS_ALLINPUT);
      MSG msg;
      while (::PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE))
      {
        ::TranslateMessage(&msg);
        ::DispatchMessageW(&msg);
      }
    }

  private:
    HANDLE timer_;
  };

  struct TabWindowDrag
  {
    HWND hwnd;
    LONG offset_x; // Cursor position inside the window rect, physical pixels.
    LONG offset_y;
    std::string merge_payload; // Empty when the window cannot merge.
    std::string label;
  };

  // Moves the window with the cursor until the left button is released, on a
  // worker thread so a busy UI thread cannot stall the move. A window that can
  // merge hides (cloaks) while it is over another window's tab strip, as Chrome
  // does, and is merged into that window when released there.
  void RunTabWindowDrag(TabWindowDrag drag)
  {
    DragTicker ticker;
    const bool mergeable = !drag.merge_payload.empty();
    POINT last{LONG_MIN, LONG_MIN};
    POINT cursor{};
    HWND hover = nullptr;
    bool cloaked = RevealHeld(drag.hwnd);
    ULONGLONG last_hover_sent = 0;

    while (::IsWindow(drag.hwnd) &&
           (::GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0)
    {
      if (::GetCursorPos(&cursor))
      {
        const bool moved = cursor.x != last.x || cursor.y != last.y;
        const ULONGLONG now = ::GetTickCount64();
        if (moved)
        {
          last = cursor;
          // Asynchronous: the window's thread applies the move, this thread
          // never waits for it.
          ::SetWindowPos(drag.hwnd, nullptr, cursor.x - drag.offset_x,
                         cursor.y - drag.offset_y, 0, 0,
                         SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                             SWP_ASYNCWINDOWPOS);
        }
        if (mergeable && moved)
        {
          const HWND target = FindTabStripHostAt(cursor, drag.hwnd);
          if (target != hover)
          {
            if (hover)
              PostTabMergeHover(hover, kTabMergeLeave, cursor);
            if (target)
              SendTabMergeData(target, drag.hwnd, kTabMergeEnter, cursor,
                               drag.label, kTabMergeEnterTimeoutMs);
            hover = target;
          }
          else if (hover)
          {
            PostTabMergeHover(hover, kTabMergeMove, cursor);
          }
          last_hover_sent = now;
        }
        else if (hover && now - last_hover_sent >= kTabMergeKeepAliveMs)
        {
          PostTabMergeHover(hover, kTabMergeMove, cursor);
          last_hover_sent = now;
        }
        const bool want_cloaked =
            hover != nullptr || RevealHeld(drag.hwnd);
        if (want_cloaked != cloaked)
        {
          cloaked = want_cloaked;
          SetWindowCloaked(drag.hwnd, cloaked);
        }
      }
      ticker.Wait();
    }

    bool merged = false;
    if (hover && ::IsWindow(drag.hwnd))
    {
      // Let the target come to the front once it has taken the tabs.
      ::AllowSetForegroundWindow(ASFW_ANY);
      merged = SendTabMergeData(hover, drag.hwnd, kTabMergeDrop, cursor,
                                drag.merge_payload, kTabMergeDropTimeoutMs);
      if (!merged)
        PostTabMergeHover(hover, kTabMergeLeave, cursor);
    }
    if (merged)
    {
      // Stay hidden: the window closes as soon as Dart hears about it.
      ::SetPropW(drag.hwnd, kMergedProp, reinterpret_cast<HANDLE>(1));
      ::PostMessageW(drag.hwnd, kTabWindowMergedMessage, 0, 0);
    }
    ::RemovePropW(drag.hwnd, kWindowDraggingProp);
    g_tab_window_drag_active.store(false);
    // Ordered against holdTabWindowHidden(false): whichever side runs last
    // sees the other's store, so a held window is always revealed once.
    if (!merged && cloaked && ::IsWindow(drag.hwnd) &&
        !RevealHeld(drag.hwnd))
    {
      SetWindowCloaked(drag.hwnd, false);
    }
  }

  std::string GetStringArgument(const flutter::EncodableMap &arguments,
                                const char *key)
  {
    const auto it = arguments.find(flutter::EncodableValue(key));
    if (it == arguments.end())
      return {};
    const auto *value = std::get_if<std::string>(&it->second);
    return value ? *value : std::string();
  }

  bool GetDoubleArgument(const flutter::EncodableMap &arguments,
                         const char *key, double *out)
  {
    const auto it = arguments.find(flutter::EncodableValue(key));
    if (it == arguments.end())
      return false;
    if (const auto *value = std::get_if<double>(&it->second))
    {
      *out = *value;
      return true;
    }
    if (const auto *value = std::get_if<int32_t>(&it->second))
    {
      *out = static_cast<double>(*value);
      return true;
    }
    if (const auto *value = std::get_if<int64_t>(&it->second))
    {
      *out = static_cast<double>(*value);
      return true;
    }
    return false;
  }

  // ---- Tab tear-off preview ------------------------------------------------
  //
  // Pulling a tab out of the strip shows this preview at once, from the source
  // process, on a thread of its own: the window that will hold the tab is
  // still loading it (cloaked) and its UI thread is busy, so moving that
  // window would lag behind the cursor. On release the real window is placed
  // where the preview is and revealed, or the tabs go to the strip under the
  // cursor.

  enum TearOffOutcome
  {
    kTearOffDetached = 0,
    kTearOffMerged = 1,
    kTearOffReturned = 2,
    kTearOffCanceled = 3,
    // Detached, and the readied window already took the preview's place.
    kTearOffRevealed = 4,
  };

  struct TearOffResult
  {
    int outcome = kTearOffCanceled;
    POINT cursor{};
    POINT window_origin{};
  };

  static std::mutex g_tear_off_mutex;
  static TearOffResult g_tear_off_result;
  static std::atomic<bool> g_tear_off_end_requested{false};
  // Identifies the newest tear-off; an older preview still held stops.
  static std::atomic<unsigned> g_tear_off_generation{0};
  static std::atomic<HWND> g_tear_off_ghost{nullptr};
  // The window readied for the tabs (another process), once it is known.
  static std::atomic<HWND> g_tear_off_target{nullptr};
  constexpr UINT kTearOffRevealTimeoutMs = 500;

  // Sent by the preview's thread to the readied window on release: place your
  // content's top-left at the point in wParam and appear.
  UINT TearOffRevealMessage()
  {
    static const UINT message =
        ::RegisterWindowMessageW(L"CBFileHub.TabTearOffReveal.v1");
    return message;
  }

  WPARAM PackScreenPoint(POINT point)
  {
    return static_cast<WPARAM>(
        (static_cast<uint64_t>(static_cast<uint32_t>(point.x)) << 32) |
        static_cast<uint32_t>(point.y));
  }

  POINT UnpackScreenPoint(WPARAM packed)
  {
    const auto value = static_cast<uint64_t>(packed);
    return POINT{static_cast<LONG>(static_cast<int32_t>(value >> 32)),
                 static_cast<LONG>(static_cast<int32_t>(value & 0xFFFFFFFF))};
  }

  // Moves [hwnd] so the top-left of its Flutter [view] is at [point].
  void PlaceWindowClientAt(HWND hwnd, HWND view, POINT point)
  {
    if (::IsZoomed(hwnd))
      ::ShowWindow(hwnd, SW_RESTORE);
    RECT window_rect{};
    POINT origin{0, 0};
    if (!::GetWindowRect(hwnd, &window_rect) ||
        !::ClientToScreen(view, &origin))
      return;
    ::SetWindowPos(hwnd, nullptr, point.x - (origin.x - window_rect.left),
                   point.y - (origin.y - window_rect.top), 0, 0,
                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }

  struct TearOffGhost
  {
    HWND source;
    int width;
    int height;
    LONG offset_x; // Cursor position inside the preview.
    LONG offset_y;
    uint32_t body_color;  // 0xAARRGGBB, not premultiplied.
    uint32_t strip_color; // 0xAARRGGBB, not premultiplied.
    int strip_height;
    int radius;
    std::vector<uint32_t> content; // Below the strip, when captured.
    int content_width = 0;
    int content_height = 0;
    std::vector<uint32_t> tab;
    int tab_width = 0;
    int tab_height = 0;
    POINT tab_position{};
    std::string payload;
    std::string label;
    unsigned generation = 0;
  };

  // [rect] of the screen as 0x??RRGGBB pixels, top-down.
  bool CaptureScreenRect(const RECT &rect, std::vector<uint32_t> *out,
                         int *width, int *height)
  {
    const int w = rect.right - rect.left;
    const int h = rect.bottom - rect.top;
    if (w <= 0 || h <= 0)
      return false;
    HDC screen = ::GetDC(nullptr);
    HDC memory = ::CreateCompatibleDC(screen);
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = w;
    info.bmiHeader.biHeight = -h;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HBITMAP bitmap =
        ::CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    bool ok = false;
    if (bitmap && bits)
    {
      HGDIOBJ previous = ::SelectObject(memory, bitmap);
      ok = ::BitBlt(memory, 0, 0, w, h, screen, rect.left, rect.top,
                    SRCCOPY) != FALSE;
      ::GdiFlush();
      if (ok)
      {
        const auto *pixels = static_cast<const uint32_t *>(bits);
        out->assign(pixels, pixels + static_cast<size_t>(w) * h);
        *width = w;
        *height = h;
      }
      ::SelectObject(memory, previous);
    }
    if (bitmap)
      ::DeleteObject(bitmap);
    ::DeleteDC(memory);
    ::ReleaseDC(nullptr, screen);
    return ok;
  }

  uint32_t Premultiply(uint32_t rgb, uint32_t alpha)
  {
    const uint32_t r = ((rgb >> 16) & 0xFF) * alpha / 255;
    const uint32_t g = ((rgb >> 8) & 0xFF) * alpha / 255;
    const uint32_t b = (rgb & 0xFF) * alpha / 255;
    return (alpha << 24) | (r << 16) | (g << 8) | b;
  }

  uint32_t ScalePixel(uint32_t pixel, double coverage)
  {
    const auto scale = [coverage](uint32_t channel) {
      return static_cast<uint32_t>(channel * coverage + 0.5);
    };
    return (scale(pixel >> 24) << 24) | (scale((pixel >> 16) & 0xFF) << 16) |
           (scale((pixel >> 8) & 0xFF) << 8) | scale(pixel & 0xFF);
  }

  // The preview: strip band and body in the window's colors, the captured tab
  // at the first tab's place, the captured content (when the tab was active),
  // rounded corners. Premultiplied BGRA for UpdateLayeredWindow.
  std::vector<uint32_t> ComposeTearOffGhost(const TearOffGhost &g)
  {
    constexpr uint32_t kBodyAlpha = 235;
    constexpr uint32_t kStripAlpha = 245;
    const int w = g.width;
    const int h = g.height;
    std::vector<uint32_t> pixels(static_cast<size_t>(w) * h);
    const uint32_t strip = Premultiply(g.strip_color, kStripAlpha);
    const uint32_t body = Premultiply(g.body_color, kBodyAlpha);
    for (int y = 0; y < h; ++y)
    {
      std::fill(pixels.begin() + static_cast<size_t>(y) * w,
                pixels.begin() + static_cast<size_t>(y + 1) * w,
                y < g.strip_height ? strip : body);
    }
    const auto blit = [&](const std::vector<uint32_t> &source, int sw, int sh,
                          int dx, int dy, uint32_t alpha) {
      for (int y = 0; y < sh; ++y)
      {
        const int ty = dy + y;
        if (ty < 0 || ty >= h)
          continue;
        for (int x = 0; x < sw; ++x)
        {
          const int tx = dx + x;
          if (tx < 0 || tx >= w)
            continue;
          pixels[static_cast<size_t>(ty) * w + tx] = Premultiply(
              source[static_cast<size_t>(y) * sw + x] & 0xFFFFFF, alpha);
        }
      }
    };
    if (!g.content.empty())
      blit(g.content, g.content_width, g.content_height, 0, g.strip_height,
           kBodyAlpha);
    if (!g.tab.empty())
      blit(g.tab, g.tab_width, g.tab_height, g.tab_position.x,
           g.tab_position.y, 255);

    const int r = std::min(g.radius, std::min(w, h) / 2);
    for (int y = 0; y < r; ++y)
    {
      for (int x = 0; x < r; ++x)
      {
        const double dx = r - x - 0.5;
        const double dy = r - y - 0.5;
        const double coverage =
            std::clamp(r - std::sqrt(dx * dx + dy * dy) + 0.5, 0.0, 1.0);
        if (coverage >= 1.0)
          continue;
        const int corners[4][2] = {
            {x, y}, {w - 1 - x, y}, {x, h - 1 - y}, {w - 1 - x, h - 1 - y}};
        for (const auto &corner : corners)
        {
          auto &pixel = pixels[static_cast<size_t>(corner[1]) * w + corner[0]];
          pixel = ScalePixel(pixel, coverage);
        }
      }
    }
    return pixels;
  }

  void RegisterTearOffGhostClass()
  {
    static std::once_flag registered;
    std::call_once(registered, []() {
      WNDCLASSEXW window_class{};
      window_class.cbSize = sizeof(window_class);
      window_class.lpfnWndProc = ::DefWindowProcW;
      window_class.hInstance = ::GetModuleHandleW(nullptr);
      window_class.lpszClassName = kTearOffGhostClass;
      ::RegisterClassExW(&window_class);
    });
  }

  HWND CreateTearOffGhostWindow(const TearOffGhost &g, POINT position)
  {
    RegisterTearOffGhostClass();
    HWND ghost = ::CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE |
            WS_EX_TRANSPARENT,
        kTearOffGhostClass, L"", WS_POPUP, position.x, position.y, g.width,
        g.height, nullptr, nullptr, ::GetModuleHandleW(nullptr), nullptr);
    if (!ghost)
      return nullptr;

    const std::vector<uint32_t> pixels = ComposeTearOffGhost(g);
    HDC screen = ::GetDC(nullptr);
    HDC memory = ::CreateCompatibleDC(screen);
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = g.width;
    info.bmiHeader.biHeight = -g.height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HBITMAP bitmap =
        ::CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (bitmap && bits)
    {
      memcpy(bits, pixels.data(), pixels.size() * sizeof(uint32_t));
      HGDIOBJ previous = ::SelectObject(memory, bitmap);
      SIZE size{g.width, g.height};
      POINT origin{0, 0};
      BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
      ::UpdateLayeredWindow(ghost, screen, &position, &size, memory, &origin, 0,
                            &blend, ULW_ALPHA);
      ::SelectObject(memory, previous);
    }
    if (bitmap)
      ::DeleteObject(bitmap);
    ::DeleteDC(memory);
    ::ReleaseDC(nullptr, screen);
    ::ShowWindow(ghost, SW_SHOWNOACTIVATE);
    return ghost;
  }

  void RunTearOffGhost(TearOffGhost g)
  {
    POINT cursor{};
    ::GetCursorPos(&cursor);
    HWND ghost = CreateTearOffGhostWindow(
        g, POINT{cursor.x - g.offset_x, cursor.y - g.offset_y});
    g_tear_off_ghost.store(ghost);

    DragTicker ticker;
    POINT last = cursor;
    HWND hover = nullptr;
    bool ghost_visible = ghost != nullptr;
    bool escaped = false;
    ULONGLONG last_hover_sent = 0;
    while ((::GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0)
    {
      if ((::GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0)
      {
        escaped = true;
        break;
      }
      if (::GetCursorPos(&cursor))
      {
        const bool moved = cursor.x != last.x || cursor.y != last.y;
        const ULONGLONG now = ::GetTickCount64();
        if (moved)
        {
          last = cursor;
          // Owned by this thread, so the move is immediate.
          if (ghost)
            ::SetWindowPos(ghost, HWND_TOPMOST, cursor.x - g.offset_x,
                           cursor.y - g.offset_y, 0, 0,
                           SWP_NOSIZE | SWP_NOACTIVATE);
          const HWND target = FindTabStripHostAt(cursor, ghost);
          if (target != hover)
          {
            if (hover)
              PostTabMergeHover(hover, kTabMergeLeave, cursor);
            if (target)
              SendTabMergeData(target, g.source, kTabMergeEnter, cursor,
                               g.label, kTabMergeEnterTimeoutMs);
            hover = target;
          }
          else if (hover)
          {
            PostTabMergeHover(hover, kTabMergeMove, cursor);
          }
          last_hover_sent = now;
        }
        else if (hover && now - last_hover_sent >= kTabMergeKeepAliveMs)
        {
          PostTabMergeHover(hover, kTabMergeMove, cursor);
          last_hover_sent = now;
        }
        // Over a tab strip the strip's gap shows where the tab lands.
        const bool want_visible = ghost && hover == nullptr;
        if (want_visible != ghost_visible)
        {
          ghost_visible = want_visible;
          ::ShowWindow(ghost, want_visible ? SW_SHOWNOACTIVATE : SW_HIDE);
        }
      }
      ticker.WaitPumping();
    }

    const POINT window_origin{cursor.x - g.offset_x, cursor.y - g.offset_y};
    int outcome = kTearOffDetached;
    if (escaped)
    {
      outcome = kTearOffCanceled;
    }
    else if (hover == g.source)
    {
      outcome = kTearOffReturned;
    }
    else if (hover)
    {
      ::AllowSetForegroundWindow(ASFW_ANY);
      if (SendTabMergeData(hover, g.source, kTabMergeDrop, cursor, g.payload,
                           kTabMergeDropTimeoutMs))
        outcome = kTearOffMerged;
    }
    if (hover && outcome != kTearOffMerged)
      PostTabMergeHover(hover, kTabMergeLeave, cursor);
    if (outcome == kTearOffDetached && ghost && !ghost_visible)
      ::ShowWindow(ghost, SW_SHOWNOACTIVATE);
    if (outcome == kTearOffDetached)
    {
      // Hand over without a round trip through either Dart side: the readied
      // window appears under the preview before the preview goes.
      const HWND target = g_tear_off_target.load();
      DWORD_PTR placed = 0;
      if (target && ::IsWindow(target))
      {
        ::AllowSetForegroundWindow(ASFW_ANY);
        if (::SendMessageTimeoutW(target, TearOffRevealMessage(),
                                  PackScreenPoint(window_origin), 0,
                                  SMTO_ABORTIFHUNG | SMTO_NORMAL,
                                  kTearOffRevealTimeoutMs, &placed) &&
            placed == 1)
          outcome = kTearOffRevealed;
      }
    }

    {
      std::lock_guard<std::mutex> lock(g_tear_off_mutex);
      g_tear_off_result.outcome = outcome;
      g_tear_off_result.cursor = cursor;
      g_tear_off_result.window_origin = window_origin;
    }
    // The mouse drag is over. Every window shares this flag now; holding it
    // while the preview below waits (up to seconds, for a window to start)
    // made the next tab drag in any window fall back to the system move
    // loop: Windows' snap bar at the top edge, and no merging.
    g_tab_window_drag_active.store(false);
    ::PostMessageW(g.source, kTabTearOffEndedMessage, 0, 0);

    // A dropped preview stays until the real window is revealed under it, or
    // until the next tear-off starts.
    if (outcome == kTearOffDetached && ghost)
    {
      const ULONGLONG until = ::GetTickCount64() + kTearOffGhostHoldMs;
      while (g_tear_off_generation.load() == g.generation &&
             !g_tear_off_end_requested.load() && ::GetTickCount64() < until)
        ticker.WaitPumping();
    }
    HWND own = ghost;
    g_tear_off_ghost.compare_exchange_strong(own, nullptr);
    if (ghost)
      ::DestroyWindow(ghost);
  }

  bool GetInt64Argument(const flutter::EncodableMap &arguments,
                        const char *key, int64_t *out)
  {
    const auto it = arguments.find(flutter::EncodableValue(key));
    if (it == arguments.end())
      return false;
    if (const auto *value = std::get_if<int32_t>(&it->second))
    {
      *out = *value;
      return true;
    }
    if (const auto *value = std::get_if<int64_t>(&it->second))
    {
      *out = *value;
      return true;
    }
    return false;
  }

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
  fullscreen_states.erase(GetTopLevelWindow(registrar_));
  RemoveTorrentNotification();
  RemoveTabStripRect();
  if (torrent_launch_hwnd_)
    ::RemovePropW(torrent_launch_hwnd_, kTorrentLaunchPriority);
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

void WindowUtilsPlugin::RemoveTorrentNotification()
{
  const HWND hwnd = torrent_notification_hwnd_;
  torrent_notification_hwnd_ = nullptr;
  if (!hwnd) return;
  ::KillTimer(hwnd, kTorrentNotificationTimer);
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = hwnd;
  icon.uID = kTorrentNotificationIcon;
  ::Shell_NotifyIconW(NIM_DELETE, &icon);
}

void WindowUtilsPlugin::PublishTabStripRect()
{
  const HWND hwnd = GetTopLevelWindow(registrar_);
  const HWND view = GetMainWindow(registrar_);
  if (!has_tab_strip_ || !hwnd || !view)
  {
    RemoveTabStripRect();
    return;
  }
  if (tab_strip_hwnd_ && tab_strip_hwnd_ != hwnd)
    RemoveTabStripRect();

  const UINT dpi = ::GetDpiForWindow(view);
  const double scale = dpi == 0 ? 1.0 : dpi / 96.0;
  POINT origin{0, 0};
  ::ClientToScreen(view, &origin);
  SetLongProp(hwnd, kTabStripLeftProp,
              origin.x + static_cast<LONG>(tab_strip_left_ * scale));
  SetLongProp(hwnd, kTabStripTopProp,
              origin.y + static_cast<LONG>(tab_strip_top_ * scale));
  SetLongProp(hwnd, kTabStripRightProp,
              origin.x + static_cast<LONG>(tab_strip_right_ * scale));
  SetLongProp(hwnd, kTabStripBottomProp,
              origin.y + static_cast<LONG>(tab_strip_bottom_ * scale));
  ::SetPropW(hwnd, kTabStripHostProp, reinterpret_cast<HANDLE>(1));
  tab_strip_hwnd_ = hwnd;
}

void WindowUtilsPlugin::RemoveTabStripRect()
{
  const HWND hwnd = tab_strip_hwnd_;
  tab_strip_hwnd_ = nullptr;
  if (!hwnd)
    return;
  ::RemovePropW(hwnd, kTabStripHostProp);
  ::RemovePropW(hwnd, kTabStripLeftProp);
  ::RemovePropW(hwnd, kTabStripTopProp);
  ::RemovePropW(hwnd, kTabStripRightProp);
  ::RemovePropW(hwnd, kTabStripBottomProp);
}

bool WindowUtilsPlugin::ScreenToTabStripPoint(POINT screen_point, double *x,
                                              double *y) const
{
  const HWND view = GetMainWindow(registrar_);
  if (!view)
    return false;
  POINT client = screen_point;
  if (!::ScreenToClient(view, &client))
    return false;
  const UINT dpi = ::GetDpiForWindow(view);
  const double scale = dpi == 0 ? 1.0 : dpi / 96.0;
  *x = client.x / scale;
  *y = client.y / scale;
  return has_tab_strip_ && *x >= tab_strip_left_ && *x < tab_strip_right_ &&
         *y >= tab_strip_top_ && *y < tab_strip_bottom_;
}

void WindowUtilsPlugin::UpdateTabMergeHover(POINT screen_point)
{
  const HWND hwnd = GetTopLevelWindow(registrar_);
  double x = 0;
  double y = 0;
  if (!hwnd || !::IsWindowVisible(hwnd) ||
      !ScreenToTabStripPoint(screen_point, &x, &y))
  {
    ClearTabMergeHover();
    return;
  }
  ::SetTimer(hwnd, kTabMergeHoverTimer, kTabMergeHoverTimeoutMs, nullptr);
  if (tab_merge_hovering_ && x == tab_merge_hover_x_ && y == tab_merge_hover_y_)
    return;
  tab_merge_hovering_ = true;
  tab_merge_hover_x_ = x;
  tab_merge_hover_y_ = y;
  if (!channel_)
    return;
  flutter::EncodableMap hover{
      {flutter::EncodableValue("x"), flutter::EncodableValue(x)},
      {flutter::EncodableValue("y"), flutter::EncodableValue(y)},
      {flutter::EncodableValue("label"),
       flutter::EncodableValue(tab_merge_label_)},
  };
  channel_->InvokeMethod("onTabMergeHover",
                         std::make_unique<flutter::EncodableValue>(hover));
}

void WindowUtilsPlugin::ClearTabMergeHover()
{
  if (const HWND hwnd = GetTopLevelWindow(registrar_))
    ::KillTimer(hwnd, kTabMergeHoverTimer);
  if (!tab_merge_hovering_)
    return;
  tab_merge_hovering_ = false;
  if (channel_)
    channel_->InvokeMethod("onTabMergeHover", nullptr);
}

bool WindowUtilsPlugin::HandleTabMergeMessage(HWND hwnd, UINT message,
                                              WPARAM wparam, LPARAM lparam,
                                              LRESULT *result)
{
  switch (message)
  {
  case kFocusHandoffMessage:
    if (g_focus_handoff.window == hwnd)
      ::SetForegroundWindow(hwnd);
    *result = 0;
    return true;
  case WM_MOUSEACTIVATE:
    // The user clicked this window: it may come forward.
    if (hwnd != g_focus_handoff.window)
      g_focus_handoff = {};
    return false;
  case WM_WINDOWPOSCHANGING:
    // Activation by a focus request would raise this window over the one
    // just handed the focus; keep it where it is.
    if (YieldsFocus(hwnd))
      reinterpret_cast<WINDOWPOS *>(lparam)->flags |= SWP_NOZORDER;
    return false;
  case WM_ACTIVATE:
    if (LOWORD(wparam) == WA_ACTIVE && YieldsFocus(hwnd))
      ::PostMessageW(g_focus_handoff.window, kFocusHandoffMessage, 0, 0);
    return false;
  default:
    break;
  }
  if (message == TearOffRevealMessage() && message != 0)
  {
    // Only a window readied for a tear-off (held hidden) takes this.
    if (!RevealHeld(hwnd))
    {
      *result = 0;
      return true;
    }
    if (const HWND view = GetMainWindow(registrar_))
      PlaceWindowClientAt(hwnd, view, UnpackScreenPoint(wparam));
    SetRevealHeld(hwnd, false);
    EngineWindowHost::RevealPrepared(hwnd);
    SetWindowCloaked(hwnd, false);
    BeginFocusHandoff(hwnd);
    ::SetForegroundWindow(hwnd);
    if (channel_)
      channel_->InvokeMethod("onTabWindowRevealed", nullptr);
    *result = 1;
    return true;
  }
  if (message == TabMergeMessage() && message != 0)
  {
    if (wparam == kTabMergeMove)
    {
      UpdateTabMergeHover(POINT{static_cast<SHORT>(LOWORD(lparam)),
                                static_cast<SHORT>(HIWORD(lparam))});
    }
    else
    {
      ClearTabMergeHover();
    }
    *result = 0;
    return true;
  }
  switch (message)
  {
  case WM_TIMER:
    if (wparam != kTabMergeHoverTimer)
      return false;
    ClearTabMergeHover();
    *result = 0;
    return true;
  case kTabWindowMergedMessage:
    if (channel_)
      channel_->InvokeMethod("onTabWindowMerged", nullptr);
    *result = 0;
    return true;
  case kTabTearOffEndedMessage:
  {
    TearOffResult ended;
    {
      std::lock_guard<std::mutex> lock(g_tear_off_mutex);
      ended = g_tear_off_result;
    }
    double drop_x = 0;
    double drop_y = 0;
    // Fills the logical point even outside the strip.
    ScreenToTabStripPoint(ended.cursor, &drop_x, &drop_y);
    static const char *const kOutcomes[] = {"detached", "merged", "returned",
                                            "canceled", "revealed"};
    const int outcome =
        ended.outcome >= 0 && ended.outcome <= 4 ? ended.outcome : 3;
    if (channel_)
    {
      flutter::EncodableMap ended_map{
          {flutter::EncodableValue("outcome"),
           flutter::EncodableValue(kOutcomes[outcome])},
          {flutter::EncodableValue("windowX"),
           flutter::EncodableValue(
               static_cast<double>(ended.window_origin.x))},
          {flutter::EncodableValue("windowY"),
           flutter::EncodableValue(
               static_cast<double>(ended.window_origin.y))},
          {flutter::EncodableValue("dropX"), flutter::EncodableValue(drop_x)},
          {flutter::EncodableValue("dropY"), flutter::EncodableValue(drop_y)},
      };
      channel_->InvokeMethod(
          "onTabTearOffEnded",
          std::make_unique<flutter::EncodableValue>(ended_map));
    }
    *result = 0;
    return true;
  }
  case WM_WINDOWPOSCHANGED:
  case WM_DPICHANGED:
    // The strip moves with the window; other processes read its position.
    if (has_tab_strip_)
      PublishTabStripRect();
    return false;
  case WM_DESTROY:
    has_tab_strip_ = false;
    RemoveTabStripRect();
    return false;
  case WM_COPYDATA:
    break;
  default:
    return false;
  }

  const auto *data = reinterpret_cast<const COPYDATASTRUCT *>(lparam);
  if (!data || (data->dwData != kTabMergeEnter && data->dwData != kTabMergeDrop))
    return false;
  *result = FALSE;
  if (!data->lpData || data->cbData < sizeof(TabMergeHeader) ||
      data->cbData > kTabMergeMaxBytes)
    return true;

  TabMergeHeader header{};
  memcpy(&header, data->lpData, sizeof(header));
  const char *text = static_cast<const char *>(data->lpData) + sizeof(header);
  std::string body(text, data->cbData - sizeof(header));
  const POINT point{header.x, header.y};

  if (data->dwData == kTabMergeEnter)
  {
    tab_merge_label_ = std::move(body);
    // Resend so Dart gets the new label even at an unchanged position.
    tab_merge_hovering_ = false;
    UpdateTabMergeHover(point);
    *result = tab_merge_hovering_ ? TRUE : FALSE;
    return true;
  }

  double x = 0;
  double y = 0;
  if (body.empty() || !::IsWindowVisible(hwnd) ||
      !ScreenToTabStripPoint(point, &x, &y))
  {
    ClearTabMergeHover();
    return true;
  }
  // Dart drops its hover indicator together with the drop.
  ::KillTimer(hwnd, kTabMergeHoverTimer);
  tab_merge_hovering_ = false;
  if (channel_)
  {
    flutter::EncodableMap drop{
        {flutter::EncodableValue("payload"), flutter::EncodableValue(body)},
        {flutter::EncodableValue("x"), flutter::EncodableValue(x)},
        {flutter::EncodableValue("y"), flutter::EncodableValue(y)},
    };
    channel_->InvokeMethod("onTabMergeDrop",
                           std::make_unique<flutter::EncodableValue>(drop));
  }
  BeginFocusHandoff(hwnd);
  ::SetForegroundWindow(hwnd);
  *result = TRUE;
  return true;
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
  drop_target_ = new TabDropTarget(channel_.get(), registrar_->GetView()->GetNativeWindow());

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
        LRESULT tab_merge_result = 0;
        if (HandleTabMergeMessage(hwnd, message, wparam, lparam,
                                  &tab_merge_result))
          return tab_merge_result;
        if (message == kTorrentNotificationMessage && wparam == kTorrentNotificationIcon)
        {
          if (lparam == NIN_BALLOONUSERCLICK || lparam == WM_LBUTTONUP || lparam == NIN_SELECT)
          {
            RemoveTorrentNotification();
            // Activation is reserved for an explicit click on the notification.
            ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
            ::SetForegroundWindow(hwnd);
            channel_->InvokeMethod("onTorrentNotificationClicked", nullptr);
          }
          return 0;
        }
        if (message == WM_TIMER && wparam == kTorrentNotificationTimer)
        {
          RemoveTorrentNotification();
          return 0;
        }
        if (message == WM_COPYDATA && ::GetPropW(hwnd, kTorrentLaunchPriority))
        {
          std::vector<std::string> sources;
          if (ReadTorrentLaunchMessage(reinterpret_cast<COPYDATASTRUCT*>(lparam), &sources))
          {
            flutter::EncodableList values;
            for (const auto& source : sources) values.emplace_back(source);
            channel_->InvokeMethod("onNativeTorrentSources",
                std::make_unique<flutter::EncodableValue>(values));
            return TRUE;
          }
        }
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
            ScheduleBackdropReapplyForPluginInstance(target, this->backdrop_active_);
          }
          break;

        case WM_NCACTIVATE:
          // Non-client area activation also triggers a DWM accent reset.
          if (wparam != FALSE)
          {
            HWND root = ::GetAncestor(hwnd, GA_ROOT);
            HWND target = root ? root : hwnd;
            ScheduleBackdropReapplyForPluginInstance(target, this->backdrop_active_);
          }
          break;

        case WM_SIZE:
          // Only a size or state change can discard the material. A tab
          // title's frame refresh repeats the same size and must not rebuild.
          if (wparam != this->backdrop_size_type_ ||
              lparam != this->backdrop_client_size_)
          {
            this->backdrop_state_.material_lost = true;
          }
          this->backdrop_size_type_ = wparam;
          this->backdrop_client_size_ = lparam;
          if (wparam == SIZE_RESTORED || wparam == SIZE_MAXIMIZED)
          {
            ScheduleBackdropReapplyForPluginInstance(hwnd, this->backdrop_active_);
          }
          break;

        case WM_SHOWWINDOW:
          if (wparam)
            this->backdrop_state_.material_lost = true;
          ScheduleBackdropReapplyForPluginInstance(hwnd, this->backdrop_active_);
          break;

        case WM_EXITSIZEMOVE:
          ScheduleBackdropReapplyForPluginInstance(hwnd, this->backdrop_active_);
          break;

        case WM_TIMER:
          if (wparam == 0xCBA0 || wparam == 0xCBA1 || wparam == 0xCBA2 || wparam == 0xCBA3)
          {
            ::KillTimer(hwnd, static_cast<UINT_PTR>(wparam));
            // The first timer rebuilds a lost material; later ones only
            // refresh, so a single event no longer flashes it four times.
            ReapplyBackdropForPluginInstance(
                this->registrar_, this->backdrop_state_, hwnd,
                this->backdrop_active_, this->backdrop_prefer_acrylic_,
                this->backdrop_dark_mode_);
          }
          break;

        case WM_THEMECHANGED:
        case WM_DWMCOMPOSITIONCHANGED:
        {
          // Full re-apply on DWM composition/theme change events.
          this->backdrop_state_.material_lost = true;
          ScheduleBackdropReapplyForPluginInstance(hwnd, this->backdrop_active_);
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

  if (method == "notifyTorrent")
  {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!args || !hwnd) {
      result->Error("INVALID_NOTIFICATION", "Notification arguments or window unavailable.");
      return;
    }
    const auto title_it = args->find(flutter::EncodableValue("title"));
    const auto body_it = args->find(flutter::EncodableValue("body"));
    const auto error_it = args->find(flutter::EncodableValue("isError"));
    const auto* title = title_it == args->end() ? nullptr : std::get_if<std::string>(&title_it->second);
    const auto* body = body_it == args->end() ? nullptr : std::get_if<std::string>(&body_it->second);
    const auto* is_error = error_it == args->end() ? nullptr : std::get_if<bool>(&error_it->second);
    if (!title || !body) {
      result->Error("INVALID_NOTIFICATION", "Notification text is required.");
      return;
    }
    // A cold background launch stays minimized; never restore or take focus.
    if (!::IsWindowVisible(hwnd)) ::ShowWindow(hwnd, SW_SHOWMINNOACTIVE);
    if (::GetForegroundWindow() != hwnd) {
      FLASHWINFO flash{sizeof(FLASHWINFO), hwnd, FLASHW_TRAY, 3, 0};
      ::FlashWindowEx(&flash);
    }
    NOTIFYICONDATAW icon{};
    icon.cbSize = sizeof(icon);
    icon.hWnd = hwnd;
    icon.uID = kTorrentNotificationIcon;
    if (!torrent_notification_hwnd_) {
      icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
      icon.uCallbackMessage = kTorrentNotificationMessage;
      icon.hIcon = ::LoadIconW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
      wcscpy_s(icon.szTip, L"CB File Hub");
      if (!::Shell_NotifyIconW(NIM_ADD, &icon)) {
        result->Success(flutter::EncodableValue(false));
        return;
      }
      torrent_notification_hwnd_ = hwnd;
    }
    icon.uFlags = NIF_INFO;
    wcsncpy_s(icon.szInfoTitle, Utf8ToWide(*title).c_str(), _TRUNCATE);
    wcsncpy_s(icon.szInfo, Utf8ToWide(*body).c_str(), _TRUNCATE);
    icon.dwInfoFlags = (is_error && *is_error ? NIIF_ERROR : NIIF_INFO) | NIIF_RESPECT_QUIET_TIME;
    const bool shown = ::Shell_NotifyIconW(NIM_MODIFY, &icon) != FALSE;
    // Keep one transient icon while Windows queues successive notifications.
    // Clean up even when Focus Assist suppresses the balloon callbacks.
    ::SetTimer(hwnd, kTorrentNotificationTimer, 120000, nullptr);
    result->Success(flutter::EncodableValue(shown));
    return;
  }

  if (method == "setTorrentLaunchPriority")
  {
    const auto* priority = std::get_if<int32_t>(method_call.arguments());
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (torrent_launch_hwnd_)
      ::RemovePropW(torrent_launch_hwnd_, kTorrentLaunchPriority);
    torrent_launch_hwnd_ = nullptr;
    if (hwnd && priority && *priority >= 1 && *priority <= 3)
    {
      if (::SetPropW(hwnd, kTorrentLaunchPriority,
                     reinterpret_cast<HANDLE>(static_cast<INT_PTR>(*priority))))
        torrent_launch_hwnd_ = hwnd;
    }
    result->Success();
    return;
  }

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

    // Restore only if minimized (SW_RESTORE would also un-maximize), then try
    // multiple activation paths.
    ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
    ::SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    BeginFocusHandoff(hwnd);
    ::BringWindowToTop(hwnd);
    ::SetActiveWindow(hwnd);

    const BOOL ok = ::SetForegroundWindow(hwnd);
    result->Success(flutter::EncodableValue(ok != FALSE));
    return;
  }

  if (method == "fitWindowToContent")
  {
    // Resizes the window for content of width x height (logical pixels): at
    // most maxFraction of its monitor's work area, at least minWidth x
    // minHeight, around its current centre and kept inside that work area.
    HWND hwnd = GetTopLevelWindow(registrar_);
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!hwnd || !args)
    {
      result->Error("INVALID_ARGUMENTS", "Window or content size unavailable.");
      return;
    }
    const auto read_number = [args](const char *key, double fallback)
    {
      auto it = args->find(flutter::EncodableValue(key));
      if (it == args->end())
        return fallback;
      if (const auto *value = std::get_if<double>(&it->second))
        return *value;
      if (const auto *value = std::get_if<int32_t>(&it->second))
        return static_cast<double>(*value);
      return fallback;
    };
    const double content_width = read_number("width", 0);
    const double content_height = read_number("height", 0);
    const double max_fraction = read_number("maxFraction", 0.85);
    const double min_width = read_number("minWidth", 0);
    const double min_height = read_number("minHeight", 0);

    // A maximized, minimized or fullscreen window keeps the user's choice.
    RECT window_rect{};
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    if (content_width <= 0 || content_height <= 0 || fullscreen_states[hwnd].active ||
        ::IsZoomed(hwnd) || ::IsIconic(hwnd) ||
        !::GetWindowRect(hwnd, &window_rect) ||
        !::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                          &monitor_info))
    {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    const RECT &work = monitor_info.rcWork;
    const double work_width = static_cast<double>(work.right - work.left);
    const double work_height = static_cast<double>(work.bottom - work.top);
    const double scale = ::GetDpiForWindow(hwnd) / 96.0;

    const double width = content_width * scale;
    const double height = content_height * scale;
    double fit = 1.0;
    if (work_width * max_fraction / width < fit)
      fit = work_width * max_fraction / width;
    if (work_height * max_fraction / height < fit)
      fit = work_height * max_fraction / height;

    double target_width = width * fit;
    double target_height = height * fit;
    if (target_width < min_width * scale)
      target_width = min_width * scale;
    if (target_height < min_height * scale)
      target_height = min_height * scale;
    if (target_width > work_width)
      target_width = work_width;
    if (target_height > work_height)
      target_height = work_height;

    const LONG new_width = static_cast<LONG>(target_width);
    const LONG new_height = static_cast<LONG>(target_height);
    LONG left = (window_rect.left + window_rect.right) / 2 - new_width / 2;
    LONG top = (window_rect.top + window_rect.bottom) / 2 - new_height / 2;
    if (left + new_width > work.right)
      left = work.right - new_width;
    if (top + new_height > work.bottom)
      top = work.bottom - new_height;
    if (left < work.left)
      left = work.left;
    if (top < work.top)
      top = work.top;

    ::SetWindowPos(hwnd, nullptr, left, top, new_width, new_height,
                   SWP_NOZORDER | SWP_NOACTIVATE);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "startWindowDragIfMouseDown" ||
      method == "startTabWindowDrag")
  {
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (!hwnd)
    {
      result->Error("NO_WINDOW", "Top-level window handle not available.");
      return;
    }

    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    double anchor_x = 0;
    double anchor_y = 0;
    const bool has_anchor = arguments &&
                            GetDoubleArgument(*arguments, "anchorX", &anchor_x) &&
                            GetDoubleArgument(*arguments, "anchorY", &anchor_y);
    bool require_merge_target = false;
    TabWindowDrag drag{hwnd, 0, 0, {}, {}};
    if (arguments)
    {
      drag.merge_payload = GetStringArgument(*arguments, "payload");
      drag.label = GetStringArgument(*arguments, "label");
      const auto it =
          arguments->find(flutter::EncodableValue("requireMergeTarget"));
      if (it != arguments->end())
      {
        const auto *value = std::get_if<bool>(&it->second);
        require_merge_target = value && *value;
      }
    }

    const bool button_down = (::GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    // Without another tab window to merge into, the caller prefers the system
    // move loop, which keeps Aero Snap.
    if ((!button_down && !has_anchor) ||
        (require_merge_target && !HasOtherTabStripHost(hwnd)))
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

    // A maximized window cannot follow the cursor; restore it first, as
    // Chrome does when its only tab is dragged.
    if (has_anchor && button_down && ::IsZoomed(hwnd))
      ::ShowWindow(hwnd, SW_RESTORE);

    POINT cursor{};
    RECT window_rect{};
    if (!::GetCursorPos(&cursor) || !::GetWindowRect(hwnd, &window_rect))
    {
      g_tab_window_drag_active.store(false);
      result->Success(flutter::EncodableValue(false));
      return;
    }

    drag.offset_x = cursor.x - window_rect.left;
    drag.offset_y = cursor.y - window_rect.top;
    if (has_anchor)
    {
      // Put the anchor (logical, relative to the Flutter view) under the
      // cursor now: the cursor has moved since the caller measured it.
      const HWND view = GetMainWindow(registrar_);
      POINT origin{0, 0};
      if (!view || !::ClientToScreen(view, &origin))
        origin = POINT{window_rect.left, window_rect.top};
      const UINT dpi = ::GetDpiForWindow(hwnd);
      const double scale = dpi == 0 ? 1.0 : dpi / 96.0;
      drag.offset_x = origin.x - window_rect.left +
                      static_cast<LONG>(anchor_x * scale);
      drag.offset_y = origin.y - window_rect.top +
                      static_cast<LONG>(anchor_y * scale);
      ::SetWindowPos(hwnd, nullptr, cursor.x - drag.offset_x,
                     cursor.y - drag.offset_y, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }

    if (!button_down)
    {
      g_tab_window_drag_active.store(false);
      result->Success(flutter::EncodableValue(false));
      return;
    }

    ::SetPropW(hwnd, kWindowDraggingProp, reinterpret_cast<HANDLE>(1));
    std::thread(RunTabWindowDrag, std::move(drag)).detach();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "startTabTearOff")
  {
    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    HWND hwnd = GetTopLevelWindow(registrar_);
    HWND view = GetMainWindow(registrar_);
    double anchor_x = 0, anchor_y = 0, tab_left = 0, tab_top = 0,
           tab_right = 0, tab_bottom = 0, first_x = 0, first_y = 0,
           window_width = 0, window_height = 0, strip_height = 0;
    int64_t body_color = 0;
    const bool valid =
        arguments && hwnd && view &&
        GetDoubleArgument(*arguments, "anchorX", &anchor_x) &&
        GetDoubleArgument(*arguments, "anchorY", &anchor_y) &&
        GetDoubleArgument(*arguments, "tabLeft", &tab_left) &&
        GetDoubleArgument(*arguments, "tabTop", &tab_top) &&
        GetDoubleArgument(*arguments, "tabRight", &tab_right) &&
        GetDoubleArgument(*arguments, "tabBottom", &tab_bottom) &&
        GetDoubleArgument(*arguments, "firstTabX", &first_x) &&
        GetDoubleArgument(*arguments, "firstTabY", &first_y) &&
        GetDoubleArgument(*arguments, "windowWidth", &window_width) &&
        GetDoubleArgument(*arguments, "windowHeight", &window_height) &&
        GetDoubleArgument(*arguments, "stripHeight", &strip_height) &&
        GetInt64Argument(*arguments, "bodyColor", &body_color);
    std::string payload =
        arguments ? GetStringArgument(*arguments, "payload") : std::string();
    if (!valid || payload.empty() || window_width < 1 || window_height < 1 ||
        (::GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0)
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
    bool include_content = false;
    {
      const auto it =
          arguments->find(flutter::EncodableValue("includeContent"));
      if (it != arguments->end())
      {
        const auto *value = std::get_if<bool>(&it->second);
        include_content = value && *value;
      }
    }

    const UINT dpi = ::GetDpiForWindow(view);
    const double scale = dpi == 0 ? 1.0 : dpi / 96.0;
    const auto px = [scale](double logical) {
      return static_cast<LONG>(std::lround(logical * scale));
    };
    POINT origin{0, 0};
    ::ClientToScreen(view, &origin);
    RECT client{};
    ::GetClientRect(view, &client);

    TearOffGhost ghost{};
    ghost.source = hwnd;
    ghost.width = px(window_width);
    ghost.height = px(window_height);
    ghost.offset_x = px(anchor_x);
    ghost.offset_y = px(anchor_y);
    ghost.body_color = static_cast<uint32_t>(body_color);
    ghost.strip_height = px(strip_height);
    ghost.radius = px(8);
    ghost.tab_position = POINT{px(first_x), px(first_y)};
    ghost.payload = std::move(payload);
    ghost.label = GetStringArgument(*arguments, "label");

    // Captured now, before the strip animates the tab away.
    const RECT tab_rect{origin.x + px(tab_left), origin.y + px(tab_top),
                        origin.x + px(tab_right), origin.y + px(tab_bottom)};
    CaptureScreenRect(tab_rect, &ghost.tab, &ghost.tab_width,
                      &ghost.tab_height);
    {
      // The strip's own background, from its blank leading edge.
      HDC screen = ::GetDC(nullptr);
      const COLORREF strip =
          ::GetPixel(screen, origin.x + px(4), origin.y + ghost.strip_height / 2);
      ::ReleaseDC(nullptr, screen);
      ghost.strip_color =
          strip == CLR_INVALID
              ? ghost.body_color
              : 0xFF000000u | (GetRValue(strip) << 16) |
                    (GetGValue(strip) << 8) | GetBValue(strip);
    }
    if (include_content)
    {
      const RECT content_rect{
          origin.x, origin.y + ghost.strip_height,
          origin.x + std::min<LONG>(client.right, ghost.width),
          origin.y + std::min<LONG>(client.bottom, ghost.height)};
      CaptureScreenRect(content_rect, &ghost.content, &ghost.content_width,
                        &ghost.content_height);
    }

    // Order matters: an older held preview sees the new generation and goes
    // before this one's end request is reset.
    ghost.generation = ++g_tear_off_generation;
    g_tear_off_end_requested.store(false);
    g_tear_off_target.store(nullptr);
    std::thread(RunTearOffGhost, std::move(ghost)).detach();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "setTabTearOffTarget")
  {
    int64_t handle = 0;
    if (const auto *value = std::get_if<int64_t>(method_call.arguments()))
      handle = *value;
    else if (const auto *value32 = std::get_if<int32_t>(method_call.arguments()))
      handle = *value32;
    g_tear_off_target.store(
        reinterpret_cast<HWND>(static_cast<intptr_t>(handle)));
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "getTopLevelWindowHandle")
  {
    result->Success(flutter::EncodableValue(static_cast<int64_t>(
        reinterpret_cast<intptr_t>(GetTopLevelWindow(registrar_)))));
    return;
  }

  if (method == "endTabTearOff")
  {
    g_tear_off_end_requested.store(true);
    if (const HWND ghost = g_tear_off_ghost.load())
      ::PostMessageW(ghost, WM_NULL, 0, 0);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "placeWindowClientAt")
  {
    // Moves the window so its Flutter view's top-left is at a screen point.
    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    HWND hwnd = GetTopLevelWindow(registrar_);
    HWND view = GetMainWindow(registrar_);
    double x = 0;
    double y = 0;
    if (!arguments || !hwnd || !view ||
        !GetDoubleArgument(*arguments, "x", &x) ||
        !GetDoubleArgument(*arguments, "y", &y))
    {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    PlaceWindowClientAt(hwnd, view,
                        POINT{static_cast<LONG>(x), static_cast<LONG>(y)});
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "holdTabWindowHidden")
  {
    const auto *hold_value = std::get_if<bool>(method_call.arguments());
    const bool hold = hold_value && *hold_value;
    HWND hwnd = GetTopLevelWindow(registrar_);
    SetRevealHeld(hwnd, hold);
    if (hwnd)
    {
      if (hold)
      {
        SetWindowCloaked(hwnd, true);
      }
      else if (!::GetPropW(hwnd, kWindowDraggingProp) &&
               !::GetPropW(hwnd, kMergedProp))
      {
        // This window's own running drag uncloaks it on its next tick unless
        // it is over a strip. Another window's drag (a tear-off preview still
        // waiting for this window) must not keep it hidden.
        SetWindowCloaked(hwnd, false);
      }
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "showWindowInactive")
  {
    // window_manager's show ignores `inactive` and calls SetForegroundWindow.
    // With every window on one thread that now succeeds, so a window prepared
    // during a tab drag took the foreground from the source mid-drag.
    HWND hwnd = GetTopLevelWindow(registrar_);
    if (hwnd)
      ::ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    result->Success(flutter::EncodableValue(hwnd != nullptr));
    return;
  }

  if (method == "setTabStripBounds")
  {
    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    double left = 0;
    double top = 0;
    double right = 0;
    double bottom = 0;
    has_tab_strip_ = arguments && GetDoubleArgument(*arguments, "left", &left) &&
                     GetDoubleArgument(*arguments, "top", &top) &&
                     GetDoubleArgument(*arguments, "right", &right) &&
                     GetDoubleArgument(*arguments, "bottom", &bottom) &&
                     right > left && bottom > top;
    tab_strip_left_ = left;
    tab_strip_top_ = top;
    tab_strip_right_ = right;
    tab_strip_bottom_ = bottom;
    if (has_tab_strip_)
    {
      PublishTabStripRect();
    }
    else
    {
      ClearTabMergeHover();
      RemoveTabStripRect();
    }
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
    g_tab_source_window = GetTopLevelWindow(registrar_);
    const HRESULT hr = ::DoDragDrop(data_object, drop_source, DROPEFFECT_MOVE,
                                    &effect);
    g_tab_source_window = nullptr;

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
    const HWND hwnd = GetTopLevelWindow(registrar_);
    result->Success(flutter::EncodableValue(fullscreen_states[hwnd].active));
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
    const LONG_PTR desired = visible
        ? style | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX
        : (style & ~WS_SYSMENU) | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
    if (style == desired) {
      result->Success(flutter::EncodableValue(true));
      return;
    }

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

    // Dart repeats this request in bursts; only the first rebuilds.
    const bool ok =
        SetNativeSystemBackdrop(backdrop_state_, hwnd, GetMainWindow(registrar_),
                                enabled, prefer_acrylic, is_dark_mode);
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
