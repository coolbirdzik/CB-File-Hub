#include "shell_context_menu_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <commctrl.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>
#include <wrl/client.h>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }

  int size_needed =
      MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                          nullptr, 0);
  if (size_needed <= 0) {
    return std::wstring();
  }

  std::wstring wide(static_cast<size_t>(size_needed), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), size_needed);
  return wide;
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }

  int size_needed =
      WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                          nullptr, 0, nullptr, nullptr);
  if (size_needed <= 0) {
    return std::string();
  }

  std::string utf8(static_cast<size_t>(size_needed), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                      static_cast<int>(wide.size()), utf8.data(), size_needed,
                      nullptr, nullptr);
  return utf8;
}

struct ShellContextMenuState {
  Microsoft::WRL::ComPtr<IContextMenu2> menu2;
  Microsoft::WRL::ComPtr<IContextMenu3> menu3;
};

constexpr UINT_PTR kShellContextMenuSubclassId = 0xCBF1A11U;

LRESULT CALLBACK ShellContextMenuSubclassProc(HWND hwnd,
                                              UINT message,
                                              WPARAM wparam,
                                              LPARAM lparam,
                                              UINT_PTR subclass_id,
                                              DWORD_PTR ref_data) {
  if (subclass_id != kShellContextMenuSubclassId) {
    return DefSubclassProc(hwnd, message, wparam, lparam);
  }

  auto* state = reinterpret_cast<ShellContextMenuState*>(ref_data);
  if (!state) {
    return DefSubclassProc(hwnd, message, wparam, lparam);
  }

  switch (message) {
    case WM_INITMENUPOPUP:
    case WM_DRAWITEM:
    case WM_MEASUREITEM:
    case WM_MENUCHAR: {
      if (state->menu3) {
        LRESULT result = 0;
        if (SUCCEEDED(state->menu3->HandleMenuMsg2(message, wparam, lparam,
                                                  &result))) {
          return result;
        }
      }
      if (state->menu2 && message != WM_MENUCHAR) {
        state->menu2->HandleMenuMsg(message, wparam, lparam);
        return 0;
      }
      break;
    }
    default:
      break;
  }

  return DefSubclassProc(hwnd, message, wparam, lparam);
}

bool PathExists(const std::wstring& path) {
  DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES;
}

bool EqualsIgnoreCase(const std::wstring& a, const std::wstring& b) {
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL;
}

bool ShouldHideShellVerb(const std::wstring& verb) {
  if (verb.empty()) {
    return false;
  }

  static const std::vector<std::wstring> kHiddenVerbs = {
      L"open",
      L"opennew",
      L"openas",
      L"openwith",
      L"edit",
      L"cut",
      L"copy",
      L"paste",
      L"delete",
      L"rename",
      L"properties",
      L"copyto",
      L"moveto",
      L"print",
      L"printto",
      L"runas",
      L"runasuser",
      L"sendto",
      L"share",
      L"windows.modernshare",
      L"copyaspath",
      L"pintohome",
      L"unpinfromhome",
      L"pintoquickaccess",
      L"unpinfromquickaccess",
      L"pinstart",
      L"taskbarpin",
      L"restore",
      L"previousversions",
      L"includeinlibrary",
      L"addtofavorites",
  };

  for (const auto& v : kHiddenVerbs) {
    if (EqualsIgnoreCase(verb, v)) {
      return true;
    }
  }
  return false;
}

bool IsSeparator(HMENU menu, int index) {
  MENUITEMINFOW mii{};
  mii.cbSize = sizeof(mii);
  mii.fMask = MIIM_FTYPE;
  if (!GetMenuItemInfoW(menu, static_cast<UINT>(index), TRUE, &mii)) {
    return false;
  }
  return (mii.fType & MFT_SEPARATOR) != 0;
}

void RemoveRedundantSeparators(HMENU menu) {
  if (!menu) {
    return;
  }

  while (GetMenuItemCount(menu) > 0 && IsSeparator(menu, 0)) {
    RemoveMenu(menu, 0, MF_BYPOSITION);
  }

  while (GetMenuItemCount(menu) > 0 &&
         IsSeparator(menu, GetMenuItemCount(menu) - 1)) {
    RemoveMenu(menu, GetMenuItemCount(menu) - 1, MF_BYPOSITION);
  }

  for (int i = GetMenuItemCount(menu) - 2; i >= 0; --i) {
    if (IsSeparator(menu, i) && IsSeparator(menu, i + 1)) {
      RemoveMenu(menu, i + 1, MF_BYPOSITION);
    }
  }

  while (GetMenuItemCount(menu) > 0 &&
         IsSeparator(menu, GetMenuItemCount(menu) - 1)) {
    RemoveMenu(menu, GetMenuItemCount(menu) - 1, MF_BYPOSITION);
  }
}

std::wstring GetCommandVerbW(IContextMenu* context_menu, UINT cmd_offset) {
  if (!context_menu) {
    return std::wstring();
  }

  wchar_t buffer[256] = {0};
  HRESULT hr = context_menu->GetCommandString(
      cmd_offset, GCS_VERBW, nullptr, reinterpret_cast<LPSTR>(buffer),
      static_cast<UINT>(std::size(buffer)));
  if (FAILED(hr)) {
    return std::wstring();
  }

  return std::wstring(buffer);
}

void PruneShellItemsFromMenu(HMENU menu,
                             IContextMenu* context_menu,
                             UINT cmd_first,
                             UINT cmd_last,
                             bool recurse_into_submenus = true) {
  if (!menu || !context_menu) {
    return;
  }

  for (int i = GetMenuItemCount(menu) - 1; i >= 0; --i) {
    MENUITEMINFOW mii{};
    mii.cbSize = sizeof(mii);
    mii.fMask = MIIM_FTYPE | MIIM_ID | MIIM_SUBMENU;
    if (!GetMenuItemInfoW(menu, static_cast<UINT>(i), TRUE, &mii)) {
      continue;
    }

    if ((mii.fType & MFT_SEPARATOR) != 0) {
      continue;
    }

    const UINT cmd = mii.wID;
    if (cmd >= cmd_first && cmd <= cmd_last) {
      const std::wstring verb =
          GetCommandVerbW(context_menu, cmd - cmd_first);
      if (ShouldHideShellVerb(verb)) {
        RemoveMenu(menu, static_cast<UINT>(i), MF_BYPOSITION);
        continue;
      }
    }

    if (mii.hSubMenu) {
      if (!recurse_into_submenus) {
        continue;
      }
      const int initial_child_count = GetMenuItemCount(mii.hSubMenu);
      PruneShellItemsFromMenu(mii.hSubMenu, context_menu, cmd_first, cmd_last,
                              true);
      RemoveRedundantSeparators(mii.hSubMenu);
      // Some Shell extensions populate cascading menus lazily in response to
      // WM_INITMENUPOPUP. Keep an initially empty submenu so it still gets that
      // callback, but remove a submenu that became empty after pruning.
      if (initial_child_count > 0 && GetMenuItemCount(mii.hSubMenu) == 0) {
        RemoveMenu(menu, static_cast<UINT>(i), MF_BYPOSITION);
      }
      continue;
    }
  }

  RemoveRedundantSeparators(menu);
}

bool TryGetDouble(const flutter::EncodableValue& v, double& out) {
  if (const auto* d = std::get_if<double>(&v)) {
    out = *d;
    return true;
  }
  if (const auto* i = std::get_if<int32_t>(&v)) {
    out = static_cast<double>(*i);
    return true;
  }
  if (const auto* i64 = std::get_if<int64_t>(&v)) {
    out = static_cast<double>(*i64);
    return true;
  }
  return false;
}

std::optional<POINT> GetScreenPointFromArgs(HWND hwnd,
                                           const flutter::EncodableMap& args) {
  auto x_it = args.find(flutter::EncodableValue("x"));
  auto y_it = args.find(flutter::EncodableValue("y"));
  if (x_it == args.end() || y_it == args.end()) {
    return std::nullopt;
  }

  double x = 0;
  double y = 0;
  if (!TryGetDouble(x_it->second, x) || !TryGetDouble(y_it->second, y)) {
    return std::nullopt;
  }

  double device_pixel_ratio = 1.0;
  auto dpr_it = args.find(flutter::EncodableValue("devicePixelRatio"));
  if (dpr_it != args.end()) {
    double v = 1.0;
    if (TryGetDouble(dpr_it->second, v) && v > 0) {
      device_pixel_ratio = v;
    }
  }

  POINT pt{};
  pt.x = static_cast<LONG>(std::lround(x * device_pixel_ratio));
  pt.y = static_cast<LONG>(std::lround(y * device_pixel_ratio));
  if (hwnd) {
    ClientToScreen(hwnd, &pt);
  }
  return pt;
}

struct ShellMenuContext {
  Microsoft::WRL::ComPtr<IContextMenu> context_menu;
  ShellContextMenuState state;
  std::vector<PIDLIST_ABSOLUTE> pidls;
};

struct ShellSubmenuReference {
  HMENU menu = nullptr;
  int parent_position = 0;
  bool initialized = false;
};

struct LoadedShellMenuSession {
  std::string id;
  HWND hwnd = nullptr;
  ShellMenuContext shell;
  HMENU menu = nullptr;
  std::set<UINT> command_ids;
  std::map<int64_t, ShellSubmenuReference> submenus;
  std::map<HMENU, int64_t> submenu_ids;
  int64_t next_submenu_id = 1;
};

std::unique_ptr<LoadedShellMenuSession> g_loaded_shell_menu_session;
UINT64 g_next_shell_menu_session_id = 1;

void FreePidls(std::vector<PIDLIST_ABSOLUTE>& pidls) {
  for (auto* p : pidls) {
    CoTaskMemFree(p);
  }
  pidls.clear();
}

void ReleaseLoadedShellMenuSession() {
  if (!g_loaded_shell_menu_session) {
    return;
  }
  if (g_loaded_shell_menu_session->menu) {
    DestroyMenu(g_loaded_shell_menu_session->menu);
  }
  FreePidls(g_loaded_shell_menu_session->shell.pidls);
  g_loaded_shell_menu_session.reset();
}

bool HaveSameParent(const std::vector<PIDLIST_ABSOLUTE>& pidls) {
  if (pidls.size() < 2) {
    return true;
  }

  PIDLIST_ABSOLUTE first_parent = ILCloneFull(pidls.front());
  if (!first_parent) {
    return false;
  }
  ILRemoveLastID(first_parent);

  bool same_parent = true;
  for (size_t i = 1; i < pidls.size(); ++i) {
    PIDLIST_ABSOLUTE candidate_parent = ILCloneFull(pidls[i]);
    if (!candidate_parent) {
      same_parent = false;
      break;
    }
    ILRemoveLastID(candidate_parent);
    same_parent = ILIsEqual(first_parent, candidate_parent);
    ILFree(candidate_parent);
    if (!same_parent) {
      break;
    }
  }

  ILFree(first_parent);
  return same_parent;
}

bool CreateShellMenuContext(HWND hwnd,
                            const std::vector<std::wstring>& paths,
                            ShellMenuContext& out) {
  if (!hwnd || paths.empty()) {
    return false;
  }

  for (const auto& path : paths) {
    if (path.empty() || !PathExists(path)) {
      return false;
    }
  }

  out.pidls.clear();
  out.pidls.reserve(paths.size());
  for (const auto& path : paths) {
    PIDLIST_ABSOLUTE pidl = nullptr;
    HRESULT hr = SHParseDisplayName(path.c_str(), nullptr, &pidl, 0, nullptr);
    if (FAILED(hr) || !pidl) {
      FreePidls(out.pidls);
      return false;
    }
    out.pidls.push_back(pidl);
  }

  // IShellFolder::GetUIObjectOf expects every child PIDL to be relative to the
  // same parent folder. Passing children from unrelated folders can make Shell
  // extensions read invalid PIDLs or expose commands for the wrong selection.
  if (!HaveSameParent(out.pidls)) {
    FreePidls(out.pidls);
    return false;
  }

  Microsoft::WRL::ComPtr<IShellFolder> parent_folder;
  PCUITEMID_CHILD unused_child = nullptr;
  HRESULT hr = SHBindToParent(out.pidls[0], IID_PPV_ARGS(&parent_folder),
                              &unused_child);
  if (FAILED(hr) || !parent_folder) {
    FreePidls(out.pidls);
    return false;
  }

  std::vector<PCUITEMID_CHILD> children;
  children.reserve(out.pidls.size());
  for (auto* pidl : out.pidls) {
    children.push_back(ILFindLastID(pidl));  // Child ID relative to parent.
  }

  void* context_menu_raw = nullptr;
  hr = parent_folder->GetUIObjectOf(hwnd, static_cast<UINT>(children.size()),
                                    children.data(), IID_IContextMenu, nullptr,
                                    &context_menu_raw);
  out.context_menu.Attach(static_cast<IContextMenu*>(context_menu_raw));
  if (FAILED(hr) || !out.context_menu) {
    FreePidls(out.pidls);
    return false;
  }

  out.state = ShellContextMenuState{};
  out.context_menu.As(&out.state.menu3);
  if (!out.state.menu3) {
    out.context_menu.As(&out.state.menu2);
  }
  return true;
}

bool InvokeShellCommand(HWND hwnd, IContextMenu* context_menu, UINT cmd,
                        UINT cmd_first) {
  if (!hwnd || !context_menu || cmd < cmd_first) {
    return false;
  }
  CMINVOKECOMMANDINFOEX invoke{};
  invoke.cbSize = sizeof(invoke);
  invoke.fMask = CMIC_MASK_UNICODE;
  invoke.hwnd = hwnd;
  invoke.lpVerb = MAKEINTRESOURCEA(cmd - cmd_first);
  invoke.lpVerbW = MAKEINTRESOURCEW(cmd - cmd_first);
  invoke.nShow = SW_SHOWNORMAL;
  return SUCCEEDED(context_menu->InvokeCommand(
      reinterpret_cast<LPCMINVOKECOMMANDINFO>(&invoke)));
}

std::wstring GetMenuLabel(HMENU menu, int index) {
  int length =
      GetMenuStringW(menu, static_cast<UINT>(index), nullptr, 0, MF_BYPOSITION);
  if (length <= 0) {
    return std::wstring();
  }

  std::wstring raw(static_cast<size_t>(length) + 1, L'\0');
  int copied = GetMenuStringW(menu, static_cast<UINT>(index), raw.data(),
                              length + 1, MF_BYPOSITION);
  if (copied <= 0) {
    return std::wstring();
  }
  raw.resize(static_cast<size_t>(copied));

  const size_t tab = raw.find(L'\t');
  if (tab != std::wstring::npos) {
    raw.resize(tab);
  }

  std::wstring label;
  label.reserve(raw.size());
  for (size_t i = 0; i < raw.size(); ++i) {
    if (raw[i] != L'&') {
      label.push_back(raw[i]);
      continue;
    }
    if (i + 1 < raw.size() && raw[i + 1] == L'&') {
      label.push_back(L'&');
      ++i;
    }
  }
  return label;
}

int64_t RegisterShellSubmenu(LoadedShellMenuSession& session,
                             HMENU submenu,
                             int parent_position) {
  const auto existing = session.submenu_ids.find(submenu);
  if (existing != session.submenu_ids.end()) {
    return existing->second;
  }

  const int64_t submenu_id = session.next_submenu_id++;
  session.submenu_ids[submenu] = submenu_id;
  session.submenus[submenu_id] = ShellSubmenuReference{
      submenu,
      parent_position,
      false,
  };
  return submenu_id;
}

std::vector<uint8_t> EncodeMenuBitmap(HBITMAP bitmap) {
  constexpr INT_PTR kLastSystemMenuBitmap = 11;
  if (!bitmap ||
      reinterpret_cast<INT_PTR>(bitmap) <= kLastSystemMenuBitmap) {
    return {};
  }

  BITMAP bitmap_info{};
  if (GetObjectW(bitmap, sizeof(bitmap_info), &bitmap_info) == 0) {
    return {};
  }

  const int width = bitmap_info.bmWidth;
  const int height = std::abs(bitmap_info.bmHeight);
  if (width <= 0 || height <= 0 || width > 256 || height > 256) {
    return {};
  }

  const size_t pixel_size =
      static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
  std::vector<uint8_t> pixels(pixel_size);

  BITMAPINFO dib_info{};
  dib_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  dib_info.bmiHeader.biWidth = width;
  dib_info.bmiHeader.biHeight = -height;
  dib_info.bmiHeader.biPlanes = 1;
  dib_info.bmiHeader.biBitCount = 32;
  dib_info.bmiHeader.biCompression = BI_RGB;

  HDC screen_dc = GetDC(nullptr);
  if (!screen_dc) {
    return {};
  }
  const int copied_lines =
      GetDIBits(screen_dc, bitmap, 0, static_cast<UINT>(height), pixels.data(),
                &dib_info, DIB_RGB_COLORS);
  ReleaseDC(nullptr, screen_dc);
  if (copied_lines != height) {
    return {};
  }

  bool has_alpha = false;
  for (size_t i = 3; i < pixels.size(); i += 4) {
    if (pixels[i] != 0) {
      has_alpha = true;
      break;
    }
  }
  if (!has_alpha) {
    for (size_t i = 3; i < pixels.size(); i += 4) {
      pixels[i] = 0xFF;
    }
  }

  BITMAPFILEHEADER file_header{};
  file_header.bfType = 0x4D42;
  file_header.bfOffBits =
      sizeof(BITMAPFILEHEADER) + sizeof(BITMAPV4HEADER);
  file_header.bfSize =
      static_cast<DWORD>(file_header.bfOffBits + pixels.size());

  BITMAPV4HEADER image_header{};
  image_header.bV4Size = sizeof(BITMAPV4HEADER);
  image_header.bV4Width = width;
  image_header.bV4Height = -height;
  image_header.bV4Planes = 1;
  image_header.bV4BitCount = 32;
  image_header.bV4V4Compression = BI_BITFIELDS;
  image_header.bV4SizeImage = static_cast<DWORD>(pixels.size());
  image_header.bV4RedMask = 0x00FF0000;
  image_header.bV4GreenMask = 0x0000FF00;
  image_header.bV4BlueMask = 0x000000FF;
  image_header.bV4AlphaMask = 0xFF000000;
  image_header.bV4CSType = LCS_sRGB;

  std::vector<uint8_t> encoded(file_header.bfSize);
  std::memcpy(encoded.data(), &file_header, sizeof(file_header));
  std::memcpy(encoded.data() + sizeof(file_header), &image_header,
              sizeof(image_header));
  std::memcpy(encoded.data() + file_header.bfOffBits, pixels.data(),
              pixels.size());
  return encoded;
}

constexpr UINT kLoadedShellCommandFirst = 1;
constexpr UINT kLoadedShellCommandLast = 0x7FFF;

flutter::EncodableList EncodeShellMenuEntries(
    HMENU menu,
    UINT command_first,
    UINT command_last,
    LoadedShellMenuSession& session) {
  flutter::EncodableList entries;
  if (!menu) {
    return entries;
  }

  const int count = GetMenuItemCount(menu);
  for (int i = 0; i < count; ++i) {
    MENUITEMINFOW mii{};
    mii.cbSize = sizeof(mii);
    mii.fMask =
        MIIM_FTYPE | MIIM_STATE | MIIM_ID | MIIM_SUBMENU | MIIM_BITMAP;
    if (!GetMenuItemInfoW(menu, static_cast<UINT>(i), TRUE, &mii)) {
      continue;
    }

    if ((mii.fType & MFT_SEPARATOR) != 0) {
      flutter::EncodableMap separator;
      separator[flutter::EncodableValue("type")] =
          flutter::EncodableValue("separator");
      entries.emplace_back(separator);
      continue;
    }

    const std::wstring label = GetMenuLabel(menu, i);
    if (label.empty()) {
      continue;
    }

    flutter::EncodableMap entry;
    entry[flutter::EncodableValue("label")] =
        flutter::EncodableValue(WideToUtf8(label));
    entry[flutter::EncodableValue("enabled")] = flutter::EncodableValue(
        (mii.fState & (MFS_DISABLED | MFS_GRAYED)) == 0);
    entry[flutter::EncodableValue("checked")] =
        flutter::EncodableValue((mii.fState & MFS_CHECKED) != 0);
    std::vector<uint8_t> icon_bytes = EncodeMenuBitmap(mii.hbmpItem);
    if (!icon_bytes.empty()) {
      entry[flutter::EncodableValue("iconBytes")] =
          flutter::EncodableValue(icon_bytes);
    }

    if (mii.hSubMenu) {
      const int64_t submenu_id =
          RegisterShellSubmenu(session, mii.hSubMenu, i);
      entry[flutter::EncodableValue("type")] =
          flutter::EncodableValue("submenu");
      entry[flutter::EncodableValue("submenuId")] =
          flutter::EncodableValue(submenu_id);
      entries.emplace_back(entry);
      continue;
    }

    if (mii.wID < command_first || mii.wID > command_last) {
      continue;
    }
    entry[flutter::EncodableValue("type")] = flutter::EncodableValue("item");
    entry[flutter::EncodableValue("commandId")] =
        flutter::EncodableValue(static_cast<int32_t>(mii.wID));
    session.command_ids.insert(mii.wID);
    entries.emplace_back(entry);
  }
  return entries;
}

std::optional<flutter::EncodableList> LoadThirdPartyShellSubmenu(
    LoadedShellMenuSession& session,
    int64_t submenu_id) {
  const auto submenu_it = session.submenus.find(submenu_id);
  if (submenu_it == session.submenus.end() || !submenu_it->second.menu) {
    return std::nullopt;
  }

  auto& submenu = submenu_it->second;
  if (!submenu.initialized) {
    if (!SetWindowSubclass(
            session.hwnd, ShellContextMenuSubclassProc,
            kShellContextMenuSubclassId,
            reinterpret_cast<DWORD_PTR>(&session.shell.state))) {
      return std::nullopt;
    }

    SendMessageW(
        session.hwnd, WM_INITMENUPOPUP,
        reinterpret_cast<WPARAM>(submenu.menu),
        MAKELPARAM(static_cast<WORD>(submenu.parent_position), FALSE));
    RemoveWindowSubclass(session.hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId);
    submenu.initialized = true;

    PruneShellItemsFromMenu(
        submenu.menu, session.shell.context_menu.Get(),
        kLoadedShellCommandFirst, kLoadedShellCommandLast, false);
  }

  return EncodeShellMenuEntries(
      submenu.menu, kLoadedShellCommandFirst, kLoadedShellCommandLast,
      session);
}

std::optional<flutter::EncodableMap> LoadThirdPartyShellMenu(
    HWND hwnd,
    const std::vector<std::wstring>& paths) {
  ReleaseLoadedShellMenuSession();
  if (!hwnd || paths.empty()) {
    return std::nullopt;
  }

  auto session = std::make_unique<LoadedShellMenuSession>();
  session->hwnd = hwnd;
  if (!CreateShellMenuContext(hwnd, paths, session->shell)) {
    return std::nullopt;
  }

  session->menu = CreatePopupMenu();
  if (!session->menu) {
    FreePidls(session->shell.pidls);
    return std::nullopt;
  }

  if (!SetWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId,
                         reinterpret_cast<DWORD_PTR>(&session->shell.state))) {
    DestroyMenu(session->menu);
    FreePidls(session->shell.pidls);
    return std::nullopt;
  }

  UINT flags = CMF_NORMAL | CMF_EXPLORE;
  if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) {
    flags |= CMF_EXTENDEDVERBS;
  }

  HRESULT hr = session->shell.context_menu->QueryContextMenu(
      session->menu, 0, kLoadedShellCommandFirst, kLoadedShellCommandLast,
      flags);
  if (FAILED(hr)) {
    RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId);
    DestroyMenu(session->menu);
    FreePidls(session->shell.pidls);
    return std::nullopt;
  }

  PruneShellItemsFromMenu(session->menu, session->shell.context_menu.Get(),
                          kLoadedShellCommandFirst,
                          kLoadedShellCommandLast, false);

  flutter::EncodableList entries = EncodeShellMenuEntries(
      session->menu, kLoadedShellCommandFirst, kLoadedShellCommandLast,
      *session);
  RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                       kShellContextMenuSubclassId);

  if (entries.empty()) {
    DestroyMenu(session->menu);
    FreePidls(session->shell.pidls);
    return std::nullopt;
  }

  session->id = std::to_string(g_next_shell_menu_session_id++);
  flutter::EncodableMap response;
  response[flutter::EncodableValue("sessionId")] =
      flutter::EncodableValue(session->id);
  response[flutter::EncodableValue("entries")] =
      flutter::EncodableValue(entries);
  g_loaded_shell_menu_session = std::move(session);
  return response;
}

bool InvokeShellVerb(HWND hwnd,
                     const std::vector<std::wstring>& paths,
                     const std::wstring& target_verb) {
  if (!hwnd || paths.empty() || target_verb.empty()) {
    return false;
  }

  ShellMenuContext shell{};
  if (!CreateShellMenuContext(hwnd, paths, shell)) {
    return false;
  }

  HMENU menu = CreatePopupMenu();
  if (!menu) {
    FreePidls(shell.pidls);
    return false;
  }

  UINT flags = CMF_NORMAL | CMF_EXPLORE | CMF_EXTENDEDVERBS;
  constexpr UINT kCmdFirst = 1;
  constexpr UINT kCmdLast = 0x7FFF;

  HRESULT hr =
      shell.context_menu->QueryContextMenu(menu, 0, kCmdFirst, kCmdLast, flags);
  if (FAILED(hr)) {
    DestroyMenu(menu);
    FreePidls(shell.pidls);
    return false;
  }

  const UINT command_count = HRESULT_CODE(hr);
  bool invoked = false;

  for (UINT cmd_offset = 0; cmd_offset < command_count; ++cmd_offset) {
    const std::wstring verb =
        GetCommandVerbW(shell.context_menu.Get(), cmd_offset);
    if (!verb.empty() && EqualsIgnoreCase(verb, target_verb)) {
      invoked = InvokeShellCommand(hwnd, shell.context_menu.Get(),
                                   kCmdFirst + cmd_offset, kCmdFirst);
      break;
    }
  }

  DestroyMenu(menu);
  FreePidls(shell.pidls);
  return invoked;
}

bool ShowShellContextMenu(HWND hwnd,
                          const std::vector<std::wstring>& paths,
                          std::optional<POINT> screen_point) {
  ShellMenuContext shell{};
  if (!CreateShellMenuContext(hwnd, paths, shell)) {
    return false;
  }

  if (!SetWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId,
                         reinterpret_cast<DWORD_PTR>(&shell.state))) {
    FreePidls(shell.pidls);
    return false;
  }

  HMENU menu = CreatePopupMenu();
  if (!menu) {
    RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId);
    FreePidls(shell.pidls);
    return false;
  }

  UINT flags = CMF_NORMAL | CMF_EXPLORE;
  if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) {
    flags |= CMF_EXTENDEDVERBS;
  }

  constexpr UINT kCmdFirst = 1;
  constexpr UINT kCmdLast = 0x7FFF;
  HRESULT hr =
      shell.context_menu->QueryContextMenu(menu, 0, kCmdFirst, kCmdLast, flags);
  if (FAILED(hr)) {
    DestroyMenu(menu);
    RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId);
    FreePidls(shell.pidls);
    return false;
  }

  // When called from the app menu ("More options"), we typically only want the
  // shell extensions (7-Zip/WinRAR/...) and not the standard Explorer verbs
  // that the app already provides (Open/Copy/Properties/...).
  PruneShellItemsFromMenu(menu, shell.context_menu.Get(), kCmdFirst, kCmdLast);

  POINT pt{};
  if (screen_point.has_value()) {
    pt = *screen_point;
  } else {
    GetCursorPos(&pt);
  }

  SetForegroundWindow(hwnd);
  UINT cmd =
      TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x, pt.y, hwnd,
                       nullptr);
  PostMessage(hwnd, WM_NULL, 0, 0);

  if (cmd >= kCmdFirst && cmd <= kCmdLast) {
    InvokeShellCommand(hwnd, shell.context_menu.Get(), cmd, kCmdFirst);
  }

  DestroyMenu(menu);
  RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                       kShellContextMenuSubclassId);
  FreePidls(shell.pidls);
  return true;
}

struct CombinedMenuResult {
  bool shown = false;
  std::optional<std::string> action_id;
};

bool ShowMergedContextMenu(HWND hwnd,
                           const std::vector<std::wstring>& paths,
                           const std::vector<std::pair<UINT, std::wstring>>& app_items,
                           const std::map<UINT, std::string>& app_id_by_cmd,
                           std::optional<POINT> screen_point,
                           CombinedMenuResult& out) {
  out = CombinedMenuResult{};
  if (!hwnd) {
    return false;
  }

  ShellMenuContext shell{};
  if (!CreateShellMenuContext(hwnd, paths, shell)) {
    return false;
  }

  if (!SetWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId,
                         reinterpret_cast<DWORD_PTR>(&shell.state))) {
    FreePidls(shell.pidls);
    return false;
  }

  HMENU root_menu = CreatePopupMenu();
  if (!root_menu) {
    RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId);
    FreePidls(shell.pidls);
    return false;
  }

  for (const auto& item : app_items) {
    if (item.first == 0) {
      AppendMenuW(root_menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    AppendMenuW(root_menu, MF_STRING, item.first, item.second.c_str());
  }

  if (!app_items.empty()) {
    AppendMenuW(root_menu, MF_SEPARATOR, 0, nullptr);
  }

  UINT flags = CMF_NORMAL | CMF_EXPLORE;
  if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) {
    flags |= CMF_EXTENDEDVERBS;
  }

  constexpr UINT kShellCmdFirst = 1;
  constexpr UINT kShellCmdLast = 0x7FFF;
  const int insert_index = GetMenuItemCount(root_menu);
  HRESULT hr = shell.context_menu->QueryContextMenu(
      root_menu, static_cast<UINT>(insert_index), kShellCmdFirst, kShellCmdLast,
      flags);
  if (FAILED(hr)) {
    DestroyMenu(root_menu);
    RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId);
    FreePidls(shell.pidls);
    return false;
  }

  // Explorer adds a lot of default verbs ("Open", "Copy", "Properties", ...).
  // Since the app already provides those actions, keep the shell extensions
  // (7-Zip/WinRAR/...) by pruning common built-in verbs.
  PruneShellItemsFromMenu(root_menu, shell.context_menu.Get(), kShellCmdFirst,
                          kShellCmdLast);

  POINT pt{};
  if (screen_point.has_value()) {
    pt = *screen_point;
  } else {
    GetCursorPos(&pt);
  }

  out.shown = true;
  SetForegroundWindow(hwnd);
  UINT cmd = TrackPopupMenuEx(root_menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x,
                             pt.y, hwnd, nullptr);
  PostMessage(hwnd, WM_NULL, 0, 0);

  if (cmd >= kShellCmdFirst && cmd <= kShellCmdLast) {
    InvokeShellCommand(hwnd, shell.context_menu.Get(), cmd, kShellCmdFirst);
  } else {
    auto it = app_id_by_cmd.find(cmd);
    if (it != app_id_by_cmd.end()) {
      out.action_id = it->second;
    }
  }

  DestroyMenu(root_menu);
  RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                       kShellContextMenuSubclassId);
  FreePidls(shell.pidls);
  return true;
}

bool ShowCombinedContextMenu(HWND hwnd,
                             const std::vector<std::wstring>& paths,
                             const std::vector<std::pair<UINT, std::wstring>>& app_items,
                             const std::map<UINT, std::string>& app_id_by_cmd,
                             const std::wstring& shell_submenu_label,
                             std::optional<POINT> screen_point,
                             CombinedMenuResult& out) {
  out = CombinedMenuResult{};
  if (!hwnd) {
    return false;
  }

  HMENU root_menu = CreatePopupMenu();
  if (!root_menu) {
    return false;
  }

  for (const auto& item : app_items) {
    if (item.first == 0) {
      AppendMenuW(root_menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    AppendMenuW(root_menu, MF_STRING, item.first, item.second.c_str());
  }

  ShellMenuContext shell{};
  HMENU shell_menu = nullptr;
  bool has_shell_menu = CreateShellMenuContext(hwnd, paths, shell);
  if (has_shell_menu) {
    shell_menu = CreatePopupMenu();
    if (!shell_menu) {
      has_shell_menu = false;
    }
  }

  constexpr UINT kShellCmdFirst = 1;
  constexpr UINT kShellCmdLast = 0x7FFF;

  if (has_shell_menu) {
    UINT flags = CMF_NORMAL | CMF_EXPLORE;
    if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) {
      flags |= CMF_EXTENDEDVERBS;
    }

    HRESULT hr = shell.context_menu->QueryContextMenu(shell_menu, 0, kShellCmdFirst,
                                                      kShellCmdLast, flags);
    if (SUCCEEDED(hr)) {
      if (!app_items.empty()) {
        AppendMenuW(root_menu, MF_SEPARATOR, 0, nullptr);
      }
      AppendMenuW(root_menu, MF_POPUP, reinterpret_cast<UINT_PTR>(shell_menu),
                  shell_submenu_label.c_str());
    } else {
      has_shell_menu = false;
      DestroyMenu(shell_menu);
      shell_menu = nullptr;
      FreePidls(shell.pidls);
    }
  }

  if (has_shell_menu) {
    if (!SetWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                           kShellContextMenuSubclassId,
                           reinterpret_cast<DWORD_PTR>(&shell.state))) {
      DestroyMenu(root_menu);
      FreePidls(shell.pidls);
      return false;
    }
  }

  POINT pt{};
  if (screen_point.has_value()) {
    pt = *screen_point;
  } else {
    GetCursorPos(&pt);
  }

  out.shown = true;
  SetForegroundWindow(hwnd);
  UINT cmd = TrackPopupMenuEx(root_menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x,
                             pt.y, hwnd, nullptr);
  PostMessage(hwnd, WM_NULL, 0, 0);

  if (cmd >= kShellCmdFirst && cmd <= kShellCmdLast && has_shell_menu) {
    InvokeShellCommand(hwnd, shell.context_menu.Get(), cmd, kShellCmdFirst);
  } else {
    auto it = app_id_by_cmd.find(cmd);
    if (it != app_id_by_cmd.end()) {
      out.action_id = it->second;
    }
  }

  DestroyMenu(root_menu);
  if (has_shell_menu) {
    RemoveWindowSubclass(hwnd, ShellContextMenuSubclassProc,
                         kShellContextMenuSubclassId);
    FreePidls(shell.pidls);
  }
  return true;
}

}  // namespace

// static
void ShellContextMenuPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "cb_file_manager/shell_context_menu",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ShellContextMenuPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ShellContextMenuPlugin::ShellContextMenuPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

ShellContextMenuPlugin::~ShellContextMenuPlugin() {
  ReleaseLoadedShellMenuSession();
}

void ShellContextMenuPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const bool is_show_shell_menu =
      method_call.method_name().compare("showContextMenu") == 0;
  const bool is_show_merged_menu =
      method_call.method_name().compare("showMergedMenu") == 0;
  const bool is_show_combined_menu =
      method_call.method_name().compare("showCombinedMenu") == 0;
  const bool is_invoke_verb =
      method_call.method_name().compare("invokeVerb") == 0;
  const bool is_load_third_party_menu =
      method_call.method_name().compare("loadThirdPartyMenu") == 0;
  const bool is_load_context_menu_submenu =
      method_call.method_name().compare("loadContextMenuSubmenu") == 0;
  const bool is_invoke_context_menu_command =
      method_call.method_name().compare("invokeContextMenuCommand") == 0;
  const bool is_release_context_menu_session =
      method_call.method_name().compare("releaseContextMenuSession") == 0;

  if (!is_show_shell_menu && !is_show_merged_menu && !is_show_combined_menu &&
      !is_invoke_verb && !is_load_third_party_menu &&
      !is_load_context_menu_submenu &&
      !is_invoke_context_menu_command && !is_release_context_menu_session) {
    result->NotImplemented();
    return;
  }

  const auto* arguments =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGUMENTS", "Arguments must be a map.");
    return;
  }

  HWND hwnd = nullptr;
  if (registrar_ && registrar_->GetView()) {
    hwnd = registrar_->GetView()->GetNativeWindow();
  }

  if (is_invoke_context_menu_command || is_release_context_menu_session ||
      is_load_context_menu_submenu) {
    auto session_it =
        arguments->find(flutter::EncodableValue("sessionId"));
    const auto* session_id =
        session_it == arguments->end()
            ? nullptr
            : std::get_if<std::string>(&session_it->second);
    if (!session_id || session_id->empty()) {
      result->Error("INVALID_ARGUMENTS",
                    "'sessionId' must be a non-empty string.");
      return;
    }

    const bool matches_active_session =
        g_loaded_shell_menu_session &&
        g_loaded_shell_menu_session->id == *session_id;
    if (is_release_context_menu_session) {
      if (matches_active_session) {
        ReleaseLoadedShellMenuSession();
      }
      result->Success();
      return;
    }

    if (is_load_context_menu_submenu) {
      auto submenu_it =
          arguments->find(flutter::EncodableValue("submenuId"));
      int64_t submenu_id = 0;
      if (submenu_it != arguments->end()) {
        if (const auto* value32 =
                std::get_if<int32_t>(&submenu_it->second)) {
          submenu_id = static_cast<int64_t>(*value32);
        } else if (const auto* value64 =
                       std::get_if<int64_t>(&submenu_it->second)) {
          submenu_id = *value64;
        }
      }

      if (!matches_active_session || submenu_id <= 0) {
        result->Success(flutter::EncodableValue());
        return;
      }

      auto entries = LoadThirdPartyShellSubmenu(
          *g_loaded_shell_menu_session, submenu_id);
      if (entries.has_value()) {
        result->Success(flutter::EncodableValue(entries.value()));
      } else {
        result->Success(flutter::EncodableValue());
      }
      return;
    }

    auto command_it =
        arguments->find(flutter::EncodableValue("commandId"));
    UINT command_id = 0;
    if (command_it != arguments->end()) {
      if (const auto* value32 = std::get_if<int32_t>(&command_it->second)) {
        if (*value32 > 0) {
          command_id = static_cast<UINT>(*value32);
        }
      } else if (const auto* value64 =
                     std::get_if<int64_t>(&command_it->second)) {
        if (*value64 > 0 && *value64 <= 0xFFFFFFFFLL) {
          command_id = static_cast<UINT>(*value64);
        }
      }
    }

    bool invoked = false;
    if (matches_active_session && command_id > 0 &&
        g_loaded_shell_menu_session->command_ids.find(command_id) !=
            g_loaded_shell_menu_session->command_ids.end()) {
      invoked = InvokeShellCommand(
          g_loaded_shell_menu_session->hwnd,
          g_loaded_shell_menu_session->shell.context_menu.Get(), command_id, 1);
      ReleaseLoadedShellMenuSession();
    }
    result->Success(flutter::EncodableValue(invoked));
    return;
  }

  auto paths_it = arguments->find(flutter::EncodableValue("paths"));
  if (paths_it == arguments->end()) {
    result->Error("INVALID_ARGUMENTS", "Missing 'paths'.");
    return;
  }

  const auto* paths_list = std::get_if<flutter::EncodableList>(&paths_it->second);
  if (!paths_list || paths_list->empty()) {
    result->Error("INVALID_ARGUMENTS", "'paths' must be a non-empty list.");
    return;
  }

  std::vector<std::wstring> paths;
  paths.reserve(paths_list->size());
  for (const auto& item : *paths_list) {
    const auto* s = std::get_if<std::string>(&item);
    if (!s) {
      result->Error("INVALID_ARGUMENTS", "Each path must be a string.");
      return;
    }
    paths.push_back(Utf8ToWide(*s));
  }

  std::optional<POINT> screen_point = GetScreenPointFromArgs(hwnd, *arguments);

  if (is_load_third_party_menu) {
    auto response = LoadThirdPartyShellMenu(hwnd, paths);
    if (response.has_value()) {
      result->Success(flutter::EncodableValue(response.value()));
    } else {
      result->Success(flutter::EncodableValue());
    }
    return;
  }

  if (is_invoke_verb) {
    auto verb_it = arguments->find(flutter::EncodableValue("verb"));
    if (verb_it == arguments->end()) {
      result->Error("INVALID_ARGUMENTS", "Missing 'verb'.");
      return;
    }

    const auto* verb = std::get_if<std::string>(&verb_it->second);
    if (!verb || verb->empty()) {
      result->Error("INVALID_ARGUMENTS", "'verb' must be a non-empty string.");
      return;
    }

    const bool ok = InvokeShellVerb(hwnd, paths, Utf8ToWide(*verb));
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (is_show_shell_menu) {
    bool ok = ShowShellContextMenu(hwnd, paths, screen_point);
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (is_show_merged_menu || is_show_combined_menu) {
    auto items_it = arguments->find(flutter::EncodableValue("items"));
    if (items_it == arguments->end()) {
      result->Error("INVALID_ARGUMENTS", "Missing 'items'.");
      return;
    }

    const auto* items_list =
        std::get_if<flutter::EncodableList>(&items_it->second);
    if (!items_list) {
      result->Error("INVALID_ARGUMENTS", "'items' must be a list.");
      return;
    }

    std::vector<std::pair<UINT, std::wstring>> app_items;
    std::map<UINT, std::string> app_id_by_cmd;

    constexpr UINT kAppCmdFirst = 0x8000;
    UINT next_cmd = kAppCmdFirst;

    for (const auto& raw_item : *items_list) {
      const auto* item_map = std::get_if<flutter::EncodableMap>(&raw_item);
      if (!item_map) {
        result->Error("INVALID_ARGUMENTS", "Each item must be a map.");
        return;
      }

      auto type_it = item_map->find(flutter::EncodableValue("type"));
      const auto* type_str =
          (type_it != item_map->end()) ? std::get_if<std::string>(&type_it->second)
                                       : nullptr;
      if (type_str && *type_str == "separator") {
        app_items.emplace_back(0, L"");
        continue;
      }

      auto id_it = item_map->find(flutter::EncodableValue("id"));
      auto label_it = item_map->find(flutter::EncodableValue("label"));
      if (id_it == item_map->end() || label_it == item_map->end()) {
        result->Error("INVALID_ARGUMENTS", "Item must contain 'id' and 'label'.");
        return;
      }

      const auto* id = std::get_if<std::string>(&id_it->second);
      const auto* label = std::get_if<std::string>(&label_it->second);
      if (!id || !label || id->empty()) {
        result->Error("INVALID_ARGUMENTS", "Invalid item 'id' or 'label'.");
        return;
      }

      UINT cmd_id = next_cmd++;
      app_id_by_cmd[cmd_id] = *id;
      app_items.emplace_back(cmd_id, Utf8ToWide(*label));
    }

    CombinedMenuResult menu_result{};
    bool ok = false;
    if (is_show_merged_menu) {
      ok = ShowMergedContextMenu(hwnd, paths, app_items, app_id_by_cmd,
                                 screen_point, menu_result);
    } else {
      std::wstring shell_submenu_label = L"More options";
      auto label_it =
          arguments->find(flutter::EncodableValue("shellSubmenuLabel"));
      if (label_it != arguments->end()) {
        if (const auto* s = std::get_if<std::string>(&label_it->second)) {
          if (!s->empty()) {
            shell_submenu_label = Utf8ToWide(*s);
          }
        }
      }

      ok = ShowCombinedContextMenu(hwnd, paths, app_items, app_id_by_cmd,
                                   shell_submenu_label, screen_point,
                                   menu_result);
    }

    flutter::EncodableMap response;
    response[flutter::EncodableValue("shown")] =
        flutter::EncodableValue(menu_result.shown && ok);
    if (menu_result.action_id.has_value()) {
      response[flutter::EncodableValue("action")] =
          flutter::EncodableValue(menu_result.action_id.value());
    } else {
      response[flutter::EncodableValue("action")] = flutter::EncodableValue();
    }

    result->Success(flutter::EncodableValue(response));
    return;
  }
}
