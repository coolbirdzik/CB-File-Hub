#include "app_icon_plugin.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <commctrl.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include <set>
#include <winreg.h>

// ---------------------------------------------------------------------------
// Taskbar progress helpers (ITaskbarList3)
// ---------------------------------------------------------------------------
static ITaskbarList3* g_taskbar = nullptr;

static void EnsureTaskbar() {
  if (g_taskbar) return;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  HRESULT hr = CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                   IID_ITaskbarList3,
                   reinterpret_cast<void**>(&g_taskbar));
  if (SUCCEEDED(hr) && g_taskbar) g_taskbar->HrInit();
}

static void SetTaskbarProgressImpl(HWND hwnd, double fraction,
                                   bool indeterminate, bool error) {
  EnsureTaskbar();
  if (!g_taskbar || !hwnd) return;

  if (indeterminate) {
    g_taskbar->SetProgressState(hwnd, TBPF_INDETERMINATE);
    return;
  }
  if (error) {
    g_taskbar->SetProgressState(hwnd, TBPF_ERROR);
    ULONGLONG completed = static_cast<ULONGLONG>(fraction * 1000.0);
    g_taskbar->SetProgressValue(hwnd, completed, 1000ULL);
    return;
  }
  if (fraction <= 0.0) {
    g_taskbar->SetProgressState(hwnd, TBPF_NOPROGRESS);
    return;
  }
  g_taskbar->SetProgressState(hwnd, TBPF_NORMAL);
  ULONGLONG completed = static_cast<ULONGLONG>(fraction * 1000.0);
  g_taskbar->SetProgressValue(hwnd, completed, 1000ULL);
}

static void ClearTaskbarProgressImpl(HWND hwnd) {
  EnsureTaskbar();
  if (!g_taskbar || !hwnd) return;
  g_taskbar->SetProgressState(hwnd, TBPF_NOPROGRESS);
}

// Renders |label| in white on an anti-aliased red disc. GDI text carries no
// alpha, so it is drawn white-on-black first and its grey level used as
// coverage when the disc is composited.
static HICON CreateBadgeIcon(int size, const std::wstring& label) {
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = size;
  bmi.bmiHeader.biHeight = -size;
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  HDC dc = CreateCompatibleDC(nullptr);
  if (!dc) return nullptr;
  void* bits = nullptr;
  HBITMAP color =
      CreateDIBSection(dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!color || !bits) {
    if (color) DeleteObject(color);
    DeleteDC(dc);
    return nullptr;
  }
  auto* pixels = static_cast<uint32_t*>(bits);
  std::fill(pixels, pixels + size * size, 0u);
  HGDIOBJ old_bitmap = SelectObject(dc, color);

  // Shrink the font until the label fits inside the disc.
  HFONT font = nullptr;
  HGDIOBJ old_font = nullptr;
  for (int height = size * 3 / 4; height >= 6; --height) {
    font = CreateFontW(-height, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                       DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                       ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_SWISS,
                       L"Segoe UI");
    if (!font) break;
    old_font = SelectObject(dc, font);
    SIZE extent = {};
    GetTextExtentPoint32W(dc, label.c_str(), static_cast<int>(label.size()),
                          &extent);
    if (extent.cx <= size - 2 || height == 6) break;
    SelectObject(dc, old_font);
    DeleteObject(font);
    font = nullptr;
  }
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(255, 255, 255));
  RECT rect = {0, 0, size, size};
  DrawTextW(dc, label.c_str(), -1, &rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  GdiFlush();

  const float radius = size / 2.0f;
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      uint32_t& px = pixels[y * size + x];
      const float dx = x + 0.5f - radius;
      const float dy = y + 0.5f - radius;
      const float disc = (std::min)(
          1.0f, (std::max)(0.0f, radius - std::sqrt(dx * dx + dy * dy)));
      const float text = (px & 0xFF) / 255.0f;
      const auto mix = [text](int base) {
        return static_cast<uint32_t>(base + (255 - base) * text + 0.5f);
      };
      const uint32_t alpha = static_cast<uint32_t>(disc * 255.0f + 0.5f);
      px = (alpha << 24) | (mix(0xD1) << 16) | (mix(0x34) << 8) | mix(0x38);
    }
  }

  if (font) {
    SelectObject(dc, old_font);
    DeleteObject(font);
  }
  SelectObject(dc, old_bitmap);
  DeleteDC(dc);

  std::vector<uint8_t> mask_bits(((size + 15) / 16) * 2 * size, 0);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, mask_bits.data());
  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmMask = mask;
  info.hbmColor = color;
  HICON icon = mask ? CreateIconIndirect(&info) : nullptr;
  if (mask) DeleteObject(mask);
  DeleteObject(color);
  return icon;
}

// Shows |count| as an overlay on the taskbar button; 0 removes it.
static void SetTaskbarBadgeImpl(HWND hwnd, int count) {
  EnsureTaskbar();
  if (!g_taskbar || !hwnd) return;
  HWND root = GetAncestor(hwnd, GA_ROOT);
  if (!root) root = hwnd;
  if (count <= 0) {
    g_taskbar->SetOverlayIcon(root, nullptr, nullptr);
    return;
  }

  const std::wstring label = count > 99 ? L"99+" : std::to_wstring(count);
  const int size = GetSystemMetricsForDpi(SM_CXSMICON, GetDpiForWindow(root));
  HICON icon = CreateBadgeIcon(size > 0 ? size : 16, label);
  if (!icon) return;
  const std::wstring description =
      label + (count == 1 ? L" notification" : L" notifications");
  // The taskbar keeps its own copy of the icon.
  g_taskbar->SetOverlayIcon(root, icon, description.c_str());
  DestroyIcon(icon);
}

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ole32.lib")

static std::string ParseExeFromCommand(const wchar_t* cmd);
static std::string ResolveExeViaApplicationsKey(const std::string& exeName);
static std::string ResolveProgIdToExe(const std::wstring& progId);

static bool SetSelfAsDefaultForVideo(const std::string& exePath);
static bool RegisterTorrentAssociations(const std::string& exePath);
static bool RegisterFileAssociations(const std::string& exePath,
                                     const std::vector<std::string>& extensions,
                                     bool setAsDefault);
static std::vector<std::string> GetInstalledAppBrands();

// static
void AppIconPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "cb_file_manager/app_icon",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<AppIconPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

AppIconPlugin::AppIconPlugin(flutter::PluginRegistrarWindows* registrar) 
    : registrar_(registrar) {
  // A window started hidden, or an Explorer restart, gets a fresh taskbar
  // button without the overlay, so the last badge is re-applied to it.
  static const UINT taskbar_button_created =
      RegisterWindowMessageW(L"TaskbarButtonCreated");
  window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM, LPARAM) -> std::optional<LRESULT> {
        if (message == taskbar_button_created && badge_count_ > 0) {
          SetTaskbarBadgeImpl(hwnd, badge_count_);
        }
        return std::nullopt;
      });
}

AppIconPlugin::~AppIconPlugin() {
  if (window_proc_delegate_id_ != 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
  }
}

void AppIconPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  
  if (method_call.method_name().compare("extractIconFromFile") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    
    if (arguments) {
      auto exePath_it = arguments->find(flutter::EncodableValue("exePath"));
      
      if (exePath_it != arguments->end()) {
        std::string exePath = std::get<std::string>(exePath_it->second);
        
        std::vector<uint8_t> iconData;
        int iconWidth = 0;
        int iconHeight = 0;
        
        if (ExtractIconFromFile(exePath, iconData, iconWidth, iconHeight)) {
          flutter::EncodableMap response;
          response[flutter::EncodableValue("iconData")] = flutter::EncodableValue(iconData);
          response[flutter::EncodableValue("width")] = flutter::EncodableValue(iconWidth);
          response[flutter::EncodableValue("height")] = flutter::EncodableValue(iconHeight);
          
          result->Success(flutter::EncodableValue(response));
          return;
        } else {
          result->Error("ICON_EXTRACTION_FAILED", "Failed to extract icon from file: " + exePath);
          return;
        }
      }
    }
    
    result->Error("INVALID_ARGUMENTS", "Invalid or missing arguments");
    return;
  } else if (method_call.method_name().compare("getAssociatedAppPath") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    
    if (arguments) {
      auto extension_it = arguments->find(flutter::EncodableValue("extension"));
      
      if (extension_it != arguments->end()) {
        std::string extension = std::get<std::string>(extension_it->second);
        
        std::string appPath = GetAssociatedAppPath(extension);
        
        if (!appPath.empty()) {
          result->Success(flutter::EncodableValue(appPath));
          return;
        } else {
          result->Error("NO_ASSOCIATED_APP", "No associated application found for extension: " + extension);
          return;
        }
      }
    }
    
    result->Error("INVALID_ARGUMENTS", "Invalid or missing arguments");
    return;
  } else if (method_call.method_name().compare("getAppsForExtension") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto ext_it = arguments->find(flutter::EncodableValue("extension"));
      if (ext_it != arguments->end()) {
        std::string extension = std::get<std::string>(ext_it->second);
        auto apps = GetAppsForExtension(extension);
        flutter::EncodableList list;
        for (const auto& p : apps) {
          flutter::EncodableMap m;
          m[flutter::EncodableValue("path")] = flutter::EncodableValue(p.first);
          m[flutter::EncodableValue("name")] = flutter::EncodableValue(p.second);
          list.push_back(flutter::EncodableValue(m));
        }
        result->Success(flutter::EncodableValue(list));
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Invalid or missing extension");
    return;
  } else if (method_call.method_name().compare("getInstalledAppBrands") == 0) {
    auto brands = GetInstalledAppBrands();
    flutter::EncodableList list;
    for (const auto& b : brands) {
      list.push_back(flutter::EncodableValue(b));
    }
    result->Success(flutter::EncodableValue(list));
    return;
  } else if (method_call.method_name().compare("registerFileAssociations") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto exe_it = arguments->find(flutter::EncodableValue("exePath"));
      auto exts_it = arguments->find(flutter::EncodableValue("extensions"));
      if (exe_it != arguments->end() && exts_it != arguments->end()) {
        std::string exePath = std::get<std::string>(exe_it->second);
        const auto& extList = std::get<flutter::EncodableList>(exts_it->second);
        std::vector<std::string> extensions;
        extensions.reserve(extList.size());
        for (const auto& e : extList) {
          extensions.push_back(std::get<std::string>(e));
        }
        bool setAsDefault = false;
        auto def_it = arguments->find(flutter::EncodableValue("setAsDefault"));
        if (def_it != arguments->end()) {
          setAsDefault = std::get<bool>(def_it->second);
        }
        bool ok = RegisterFileAssociations(exePath, extensions, setAsDefault);
        result->Success(flutter::EncodableValue(ok));
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Invalid or missing exePath/extensions");
    return;
  } else if (method_call.method_name() == "registerTorrentAssociations") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto it = arguments->find(flutter::EncodableValue("exePath"));
      if (it != arguments->end() && std::holds_alternative<std::string>(it->second)) {
        result->Success(flutter::EncodableValue(
            RegisterTorrentAssociations(std::get<std::string>(it->second))));
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Missing exePath");
    return;
  } else if (method_call.method_name() == "openTorrentDefaultSettings") {
    const auto launched = reinterpret_cast<INT_PTR>(ShellExecuteW(
        nullptr, L"open", L"ms-settings:defaultapps?registeredAppUser=CB%20File%20Hub",
        nullptr, nullptr, SW_SHOWNORMAL));
    result->Success(flutter::EncodableValue(launched > 32));
    return;
  } else if (method_call.method_name().compare("setSelfAsDefaultForVideo") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto it = arguments->find(flutter::EncodableValue("exePath"));
      if (it != arguments->end()) {
        std::string exePath = std::get<std::string>(it->second);
        bool ok = SetSelfAsDefaultForVideo(exePath);
        result->Success(flutter::EncodableValue(ok));
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Invalid or missing exePath");
    return;
  } else if (method_call.method_name().compare("extractIconsForExtensions") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto exts_it = arguments->find(flutter::EncodableValue("extensions"));
      auto size_it = arguments->find(flutter::EncodableValue("iconSize"));
      if (exts_it != arguments->end()) {
        const auto& extList = std::get<flutter::EncodableList>(exts_it->second);
        std::vector<std::string> extensions;
        extensions.reserve(extList.size());
        for (const auto& e : extList) {
          extensions.push_back(std::get<std::string>(e));
        }
        int iconSize = 32;
        if (size_it != arguments->end()) {
          iconSize = std::get<int>(size_it->second);
        }
        ExtractIconsForExtensions(extensions, iconSize, std::move(result));
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Invalid or missing extensions list");
    return;
  } else if (method_call.method_name().compare("setTaskbarProgress") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    double fraction = 0.0;
    bool indeterminate = false;
    bool error = false;
    if (arguments) {
      auto it = arguments->find(flutter::EncodableValue("fraction"));
      if (it != arguments->end()) {
        if (std::holds_alternative<double>(it->second))
          fraction = std::get<double>(it->second);
      }
      auto it2 = arguments->find(flutter::EncodableValue("indeterminate"));
      if (it2 != arguments->end() && std::holds_alternative<bool>(it2->second))
        indeterminate = std::get<bool>(it2->second);
      auto it3 = arguments->find(flutter::EncodableValue("error"));
      if (it3 != arguments->end() && std::holds_alternative<bool>(it3->second))
        error = std::get<bool>(it3->second);
    }
    HWND hwnd = registrar_->GetView()->GetNativeWindow();
    SetTaskbarProgressImpl(hwnd, fraction, indeterminate, error);
    result->Success(flutter::EncodableValue(true));
    return;
  } else if (method_call.method_name().compare("clearTaskbarProgress") == 0) {
    HWND hwnd = registrar_->GetView()->GetNativeWindow();
    ClearTaskbarProgressImpl(hwnd);
    result->Success(flutter::EncodableValue(true));
    return;
  } else if (method_call.method_name().compare("setTaskbarBadge") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    int count = 0;
    if (arguments) {
      auto it = arguments->find(flutter::EncodableValue("count"));
      if (it != arguments->end() && std::holds_alternative<int>(it->second))
        count = std::get<int>(it->second);
    }
    badge_count_ = count;
    HWND hwnd = registrar_->GetView()->GetNativeWindow();
    SetTaskbarBadgeImpl(hwnd, count);
    result->Success(flutter::EncodableValue(true));
    return;
  } else {
    result->NotImplemented();
  }
}

bool AppIconPlugin::ExtractIconFromFile(
    const std::string& exePath,
    std::vector<uint8_t>& outputBuffer,
    int& iconWidth,
    int& iconHeight) {
    
  if (exePath.empty()) {
    return false;
  }

  // Convert UTF-8 path to wide string
  int widePathSize = MultiByteToWideChar(CP_UTF8, 0, exePath.c_str(), -1, nullptr, 0);
  if (widePathSize == 0) {
    return false;
  }
  
  std::vector<wchar_t> wExePath(widePathSize);
  if (MultiByteToWideChar(CP_UTF8, 0, exePath.c_str(), -1, wExePath.data(), widePathSize) == 0) {
    return false;
  }

  // Get the associated icon
  SHFILEINFOW fileInfo = { 0 };
  DWORD_PTR result = SHGetFileInfoW(
      wExePath.data(),
      0,
      &fileInfo,
      sizeof(fileInfo),
      SHGFI_ICON | SHGFI_LARGEICON
  );

  if (result == 0 || !fileInfo.hIcon) {
    return false;
  }

  // Extract the icon dimensions and bitmap data
  ICONINFO iconInfo;
  if (!GetIconInfo(fileInfo.hIcon, &iconInfo)) {
    DestroyIcon(fileInfo.hIcon);
    return false;
  }

  BITMAP bmp;
  if (!GetObject(iconInfo.hbmColor, sizeof(BITMAP), &bmp)) {
    DeleteObject(iconInfo.hbmMask);
    DeleteObject(iconInfo.hbmColor);
    DestroyIcon(fileInfo.hIcon);
    return false;
  }

  iconWidth = bmp.bmWidth;
  iconHeight = bmp.bmHeight;

  // Create a memory DC compatible with the screen
  HDC screenDC = GetDC(NULL);
  HDC memDC = CreateCompatibleDC(screenDC);

  // Create a compatible bitmap to hold the icon
  HBITMAP hBitmap = CreateCompatibleBitmap(screenDC, iconWidth, iconHeight);
  HBITMAP oldBitmap = (HBITMAP)SelectObject(memDC, hBitmap);

  // Fill with transparent background
  HBRUSH hBrush = CreateSolidBrush(RGB(0, 0, 0));
  RECT rect = { 0, 0, iconWidth, iconHeight };
  FillRect(memDC, &rect, hBrush);
  DeleteObject(hBrush);

  // Draw the icon on the memory DC
  DrawIconEx(memDC, 0, 0, fileInfo.hIcon, iconWidth, iconHeight, 0, NULL, DI_NORMAL);

  // Get the bitmap bits
  BITMAPINFOHEADER bmi = { 0 };
  bmi.biSize = sizeof(BITMAPINFOHEADER);
  bmi.biWidth = iconWidth;
  bmi.biHeight = -iconHeight; // Negative height for top-down
  bmi.biPlanes = 1;
  bmi.biBitCount = 32;
  bmi.biCompression = BI_RGB;

  int stride = ((iconWidth * 32 + 31) / 32) * 4;
  int imageSize = stride * iconHeight;
  
  // Resize the output buffer
  outputBuffer.resize(imageSize);

  // Get the bitmap data
  bool success = (GetDIBits(memDC, hBitmap, 0, iconHeight, outputBuffer.data(), (BITMAPINFO*)&bmi, DIB_RGB_COLORS) != 0);

  // Cleanup
  SelectObject(memDC, oldBitmap);
  DeleteObject(hBitmap);
  DeleteDC(memDC);
  ReleaseDC(NULL, screenDC);
  DeleteObject(iconInfo.hbmMask);
  DeleteObject(iconInfo.hbmColor);
  DestroyIcon(fileInfo.hIcon);

  return success;
}

static std::string ParseExeFromCommand(const wchar_t* cmd);

static bool IsCbFileHubProgId(const std::wstring& progId) {
  if (progId.empty()) return false;
  if (progId.rfind(L"CBFileHub.", 0) == 0) return true;
  std::wstring lower = progId;
  for (wchar_t& c : lower) {
    if (c >= L'A' && c <= L'Z') c = c - L'A' + L'a';
  }
  return lower.rfind(L"applications\\cb_file_hub.exe", 0) == 0;
}

static bool IsShellProxyExecutable(const std::string& path) {
  if (path.empty()) return false;
  size_t last = path.find_last_of("/\\");
  std::string name = (last != std::string::npos) ? path.substr(last + 1) : path;
  for (auto& c : name) c = (char)tolower((unsigned char)c);
  return name == "explorer.exe";
}

static std::wstring QueryDefaultProgId(const wchar_t* ext) {
  if (!ext || !*ext) return L"";

  wchar_t progId[512] = {0};
  DWORD progIdSize = (DWORD)(sizeof(progId) / sizeof(progId[0]));
  if (SUCCEEDED(AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_PROGID, ext, NULL,
                                  progId, &progIdSize)) &&
      progId[0]) {
    return std::wstring(progId);
  }

  std::wstring extKey = L"Software\\Classes\\";
  extKey += ext;
  wchar_t value[512] = {0};
  for (HKEY root : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
    HKEY hKey = NULL;
    if (RegOpenKeyExW(root, extKey.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
      continue;
    }
    DWORD valueSize = sizeof(value);
    if (RegQueryValueExW(hKey, NULL, NULL, NULL, (LPBYTE)value, &valueSize) ==
            ERROR_SUCCESS &&
        value[0]) {
      RegCloseKey(hKey);
      return std::wstring(value);
    }
    RegCloseKey(hKey);
  }

  std::wstring userChoiceKey =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\";
  userChoiceKey += ext;
  userChoiceKey += L"\\UserChoice";
  HKEY hUserChoice = NULL;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, userChoiceKey.c_str(), 0, KEY_READ,
                    &hUserChoice) == ERROR_SUCCESS) {
    wchar_t ucProgId[512] = {0};
    DWORD ucSize = sizeof(ucProgId);
    if (RegQueryValueExW(hUserChoice, L"ProgId", NULL, NULL, (LPBYTE)ucProgId,
                         &ucSize) == ERROR_SUCCESS &&
        ucProgId[0]) {
      RegCloseKey(hUserChoice);
      return std::wstring(ucProgId);
    }
    RegCloseKey(hUserChoice);
  }

  return L"";
}

static std::string ResolveOpenCommandForExtension(const wchar_t* ext) {
  if (!ext || !*ext) return "";
  wchar_t openCmd[2048] = {0};
  DWORD openCmdSize = (DWORD)(sizeof(openCmd) / sizeof(openCmd[0]));
  if (!SUCCEEDED(AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_COMMAND, ext, NULL,
                                   openCmd, &openCmdSize))) {
    return "";
  }
  return ParseExeFromCommand(openCmd);
}

std::string AppIconPlugin::GetAssociatedAppPath(const std::string& extension) {
  // Ensure extension starts with dot
  std::string ext = extension;
  if (!ext.empty() && ext[0] != '.') {
    ext = "." + ext;
  }

  // Convert extension to wide string
  int wideExtSize = MultiByteToWideChar(CP_UTF8, 0, ext.c_str(), -1, nullptr, 0);
  if (wideExtSize == 0) {
    return "";
  }
  
  std::vector<wchar_t> wExtension(wideExtSize);
  if (MultiByteToWideChar(CP_UTF8, 0, ext.c_str(), -1, wExtension.data(), wideExtSize) == 0) {
    return "";
  }

  // 1. Resolve the user's default ProgId (Settings → Default apps / UserChoice).
  const std::wstring defaultProgId = QueryDefaultProgId(wExtension.data());
  if (!defaultProgId.empty()) {
    const std::string fromProgId = ResolveProgIdToExe(defaultProgId);
    if (!fromProgId.empty()) {
      if (IsCbFileHubProgId(defaultProgId) || !IsShellProxyExecutable(fromProgId)) {
        return fromProgId;
      }
    }
  }

  // 2. Fall back to the shell "open" command for this extension.
  const std::string fromOpenCommand =
      ResolveOpenCommandForExtension(wExtension.data());
  if (!fromOpenCommand.empty() && !IsShellProxyExecutable(fromOpenCommand)) {
    return fromOpenCommand;
  }

  // 3. Last resort: ASSOCSTR_EXECUTABLE.
  wchar_t execPath[MAX_PATH] = {0};
  DWORD execPathSize = MAX_PATH;
  if (!SUCCEEDED(AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_EXECUTABLE,
                                   wExtension.data(), NULL, execPath,
                                   &execPathSize))) {
    return fromOpenCommand;
  }

  int utf8Size =
      WideCharToMultiByte(CP_UTF8, 0, execPath, -1, nullptr, 0, NULL, NULL);
  if (utf8Size == 0) {
    return fromOpenCommand;
  }
  std::vector<char> utf8Path(utf8Size);
  if (WideCharToMultiByte(CP_UTF8, 0, execPath, -1, utf8Path.data(), utf8Size,
                          NULL, NULL) == 0) {
    return fromOpenCommand;
  }

  std::string result(utf8Path.data());
  if (IsShellProxyExecutable(result)) {
    return fromOpenCommand;
  }
  return result;
}

static std::string GetDisplayNameFromPath(const std::string& path) {
  if (path.empty()) return "";
  size_t last = path.find_last_of("/\\");
  std::string name = (last != std::string::npos) ? path.substr(last + 1) : path;
  size_t dot = name.find_last_of('.');
  if (dot != std::string::npos && (name.size() - dot <= 5)) {
    name = name.substr(0, dot);
  }
  return name.empty() ? path : name;
}

static std::string ParseExeFromCommand(const wchar_t* cmd) {
  if (!cmd || !*cmd) return "";
  const wchar_t* p = cmd;
  while (*p == L' ' || *p == L'\t') p++;
  if (!*p) return "";
  std::wstring exe;
  if (*p == L'"') {
    p++;
    const wchar_t* end = wcschr(p, L'"');
    if (!end) return "";
    exe.assign(p, end - p);
    p = end + 1;
  } else {
    const wchar_t* start = p;
    while (*p && *p != L' ' && *p != L'\t' && *p != L'%') p++;
    exe.assign(start, p - start);
  }
  if (exe.empty()) return "";
  std::vector<wchar_t> expanded(32768, 0);
  DWORD n = ExpandEnvironmentStringsW(exe.c_str(), expanded.data(), (DWORD)expanded.size());
  if (n == 0 || n > expanded.size()) return "";
  int u8 = WideCharToMultiByte(CP_UTF8, 0, expanded.data(), -1, nullptr, 0, NULL, NULL);
  if (u8 <= 0) return "";
  std::vector<char> out(u8);
  if (WideCharToMultiByte(CP_UTF8, 0, expanded.data(), -1, out.data(), u8, NULL, NULL) <= 0) return "";
  return std::string(out.data());
}

static std::string ResolveExeViaApplicationsKey(const std::string& exeName) {
  if (exeName.empty()) return "";
  int wlen = MultiByteToWideChar(CP_UTF8, 0, exeName.c_str(), -1, nullptr, 0);
  if (wlen <= 0) return "";
  std::vector<wchar_t> wExe(wlen);
  if (MultiByteToWideChar(CP_UTF8, 0, exeName.c_str(), -1, wExe.data(), wlen) == 0) return "";
  std::wstring keyPath = L"SOFTWARE\\Classes\\Applications\\";
  keyPath += wExe.data();
  keyPath += L"\\shell\\open\\command";
  wchar_t cmdBuf[2048] = { 0 };
  DWORD cmdSize = (DWORD)(sizeof(cmdBuf));
  for (HKEY root : { HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER }) {
    HKEY hKey = NULL;
    if (RegOpenKeyExW(root, keyPath.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS) continue;
    cmdSize = (DWORD)(sizeof(cmdBuf));
    if (RegQueryValueExW(hKey, NULL, NULL, NULL, (LPBYTE)cmdBuf, &cmdSize) == ERROR_SUCCESS) {
      RegCloseKey(hKey);
      std::string exe = ParseExeFromCommand(cmdBuf);
      if (!exe.empty()) return exe;
    } else {
      RegCloseKey(hKey);
    }
  }
  return "";
}

static std::string ResolveProgIdToExe(const std::wstring& progId) {
  if (progId.empty()) return "";
  std::wstring keyPath = L"SOFTWARE\\Classes\\";
  keyPath += progId;
  keyPath += L"\\shell\\open\\command";
  wchar_t cmdBuf[2048] = { 0 };
  DWORD cmdSize = (DWORD)(sizeof(cmdBuf));
  for (HKEY root : { HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER }) {
    HKEY hKey = NULL;
    if (RegOpenKeyExW(root, keyPath.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS) continue;
    cmdSize = (DWORD)(sizeof(cmdBuf));
    if (RegQueryValueExW(hKey, NULL, NULL, NULL, (LPBYTE)cmdBuf, &cmdSize) == ERROR_SUCCESS) {
      RegCloseKey(hKey);
      std::string exe = ParseExeFromCommand(cmdBuf);
      if (exe.empty()) return "";
      if (exe.find("explorer.exe") != std::string::npos && exe.find("shell:") != std::string::npos)
        return "";
      return exe;
    }
    RegCloseKey(hKey);
  }
  return "";
}

static std::string ResolveExeViaAppPaths(const std::string& exeName) {
  if (exeName.empty()) return "";
  int wideSize = MultiByteToWideChar(CP_UTF8, 0, exeName.c_str(), -1, nullptr, 0);
  if (wideSize == 0) return "";
  std::vector<wchar_t> wExe(wideSize);
  if (MultiByteToWideChar(CP_UTF8, 0, exeName.c_str(), -1, wExe.data(), wideSize) == 0) {
    return "";
  }
  wchar_t pathBuf[MAX_PATH] = { 0 };
  DWORD pathSize = MAX_PATH;
  std::wstring appPathsKey = L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\";
  appPathsKey += wExe.data();
  HKEY hKey = NULL;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, appPathsKey.c_str(), 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
    if (RegQueryValueExW(hKey, NULL, NULL, NULL, (LPBYTE)pathBuf, &pathSize) == ERROR_SUCCESS) {
      RegCloseKey(hKey);
      int u8 = WideCharToMultiByte(CP_UTF8, 0, pathBuf, -1, nullptr, 0, NULL, NULL);
      if (u8 > 0) {
        std::vector<char> out(u8);
        if (WideCharToMultiByte(CP_UTF8, 0, pathBuf, -1, out.data(), u8, NULL, NULL) > 0) {
          return std::string(out.data());
        }
      }
      return "";
    }
    RegCloseKey(hKey);
  }
  if (RegOpenKeyExW(HKEY_CURRENT_USER, appPathsKey.c_str(), 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
    pathSize = MAX_PATH;
    if (RegQueryValueExW(hKey, NULL, NULL, NULL, (LPBYTE)pathBuf, &pathSize) == ERROR_SUCCESS) {
      RegCloseKey(hKey);
      int u8 = WideCharToMultiByte(CP_UTF8, 0, pathBuf, -1, nullptr, 0, NULL, NULL);
      if (u8 > 0) {
        std::vector<char> out(u8);
        if (WideCharToMultiByte(CP_UTF8, 0, pathBuf, -1, out.data(), u8, NULL, NULL) > 0) {
          return std::string(out.data());
        }
      }
    } else {
      RegCloseKey(hKey);
    }
  }
  std::string viaApps = ResolveExeViaApplicationsKey(exeName);
  if (!viaApps.empty()) return viaApps;
  wchar_t pathBuf2[MAX_PATH] = { 0 };
  if (SearchPathW(NULL, wExe.data(), NULL, MAX_PATH, pathBuf2, NULL) > 0) {
    int u8 = WideCharToMultiByte(CP_UTF8, 0, pathBuf2, -1, nullptr, 0, NULL, NULL);
    if (u8 > 0) {
      std::vector<char> out(u8);
      if (WideCharToMultiByte(CP_UTF8, 0, pathBuf2, -1, out.data(), u8, NULL, NULL) > 0) {
        return std::string(out.data());
      }
    }
  }
  return "";
}

std::vector<std::pair<std::string, std::string>> AppIconPlugin::GetAppsForExtension(
    const std::string& extension) {
  std::vector<std::pair<std::string, std::string>> results;
  std::set<std::string> seenPaths;
  std::string ext = extension;
  if (!ext.empty() && ext[0] != '.') {
    ext = "." + ext;
  }
  std::string defaultPath = GetAssociatedAppPath(ext);
  if (!defaultPath.empty() && seenPaths.find(defaultPath) == seenPaths.end()) {
    seenPaths.insert(defaultPath);
    results.push_back({ defaultPath, GetDisplayNameFromPath(defaultPath) });
  }
  std::wstring keyPath = L"SOFTWARE\\Classes\\";
  int extWide = MultiByteToWideChar(CP_UTF8, 0, ext.c_str(), -1, nullptr, 0);
  if (extWide == 0) return results;
  std::vector<wchar_t> wExt(extWide);
  if (MultiByteToWideChar(CP_UTF8, 0, ext.c_str(), -1, wExt.data(), extWide) == 0) {
    return results;
  }
  keyPath += wExt.data();
  keyPath += L"\\OpenWithList";

  auto enumOpenWithList = [&](HKEY root) {
    HKEY hKey = NULL;
    if (RegOpenKeyExW(root, keyPath.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS)
      return;
    wchar_t valueName[256];
    wchar_t valueData[256];
    DWORD valueNameLen, valueDataLen, type;
    for (DWORD i = 0; ; i++) {
      valueNameLen = 256;
      valueDataLen = sizeof(valueData);
      if (RegEnumValueW(hKey, i, valueName, &valueNameLen, NULL, &type, (LPBYTE)valueData, &valueDataLen) != ERROR_SUCCESS)
        break;
      if (_wcsicmp(valueName, L"MRUList") == 0) continue;
      if (type != REG_SZ && type != REG_EXPAND_SZ) continue;
      int u8len = WideCharToMultiByte(CP_UTF8, 0, valueData, -1, nullptr, 0, NULL, NULL);
      if (u8len == 0) continue;
      std::vector<char> exeName(u8len);
      if (WideCharToMultiByte(CP_UTF8, 0, valueData, -1, exeName.data(), u8len, NULL, NULL) == 0) continue;
      std::string exeStr(exeName.data());
      std::string path = ResolveExeViaAppPaths(exeStr);
      if (path.empty()) continue;
      if (seenPaths.find(path) != seenPaths.end()) continue;
      seenPaths.insert(path);
      results.push_back({ path, GetDisplayNameFromPath(path) });
    }
    RegCloseKey(hKey);
  };

  enumOpenWithList(HKEY_LOCAL_MACHINE);
  enumOpenWithList(HKEY_CURRENT_USER);

  std::wstring keyPathProgids = L"SOFTWARE\\Classes\\";
  keyPathProgids += wExt.data();
  keyPathProgids += L"\\OpenWithProgids";
  auto enumOpenWithProgids = [&](HKEY root) {
    HKEY hKey = NULL;
    if (RegOpenKeyExW(root, keyPathProgids.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS) return;
    wchar_t valueName[256];
    DWORD valueNameLen, type;
    for (DWORD i = 0; ; i++) {
      valueNameLen = 256;
      if (RegEnumValueW(hKey, i, valueName, &valueNameLen, NULL, &type, NULL, NULL) != ERROR_SUCCESS) break;
      std::wstring progId(valueName);
      std::string path = ResolveProgIdToExe(progId);
      if (path.empty()) continue;
      if (seenPaths.find(path) != seenPaths.end()) continue;
      seenPaths.insert(path);
      results.push_back({ path, GetDisplayNameFromPath(path) });
    }
    RegCloseKey(hKey);
  };
  enumOpenWithProgids(HKEY_LOCAL_MACHINE);
  enumOpenWithProgids(HKEY_CURRENT_USER);

  return results;
}

/// Scans registry for known office suite installations and returns brand identifiers.
static std::vector<std::string> GetInstalledAppBrands() {
  std::vector<std::string> brands;

  // Helper: check if a registry key exists (non-leaf key).
  auto keyExists = [](HKEY root, const wchar_t* path) -> bool {
    HKEY hKey = NULL;
    bool ok = RegOpenKeyExW(root, path, 0, KEY_READ, &hKey) == ERROR_SUCCESS;
    if (ok) RegCloseKey(hKey);
    return ok;
  };

  // Helper: check if a file path exists.
  auto fileExists = [](const wchar_t* path) -> bool {
    DWORD attrs = GetFileAttributesW(path);
    return attrs != INVALID_FILE_ATTRIBUTES &&
           !(attrs & FILE_ATTRIBUTE_DIRECTORY);
  };

  // Microsoft Office: check InstallRoot registry key or known paths.
  bool hasMicrosoft = false;
  const wchar_t* msPaths[] = {
    L"SOFTWARE\\Microsoft\\Office\\16.0\\Word\\InstallRoot",
    L"SOFTWARE\\Microsoft\\Office\\15.0\\Word\\InstallRoot",
    L"SOFTWARE\\Microsoft\\Office\\14.0\\Word\\InstallRoot",
    L"SOFTWARE\\Microsoft\\Office",
  };
  for (auto p : msPaths) {
    if (keyExists(HKEY_LOCAL_MACHINE, p) || keyExists(HKEY_CURRENT_USER, p)) {
      hasMicrosoft = true;
      break;
    }
  }
  if (!hasMicrosoft) {
    wchar_t winwordPath[MAX_PATH] = {0};
    if (SearchPathW(NULL, L"winword.exe", NULL, MAX_PATH, winwordPath, NULL) > 0) {
      hasMicrosoft = true;
    }
  }
  if (hasMicrosoft) brands.push_back("microsoft");

  // LibreOffice: check registry or soffice.exe in PATH.
  bool hasLibre = keyExists(HKEY_LOCAL_MACHINE, L"SOFTWARE\\LibreOffice\\InstallPath") ||
                  keyExists(HKEY_CURRENT_USER, L"SOFTWARE\\LibreOffice\\InstallPath") ||
                  keyExists(HKEY_LOCAL_MACHINE, L"SOFTWARE\\WOW6432Node\\LibreOffice\\InstallPath");
  if (!hasLibre) {
    wchar_t sofficePath[MAX_PATH] = {0};
    if (SearchPathW(NULL, L"soffice.exe", NULL, MAX_PATH, sofficePath, NULL) > 0) {
      hasLibre = true;
    }
  }
  if (hasLibre) brands.push_back("libre");

  // WPS Office: check registry paths.
  bool hasWps = keyExists(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Kingsoft\\Office") ||
                keyExists(HKEY_CURRENT_USER, L"SOFTWARE\\Kingsoft\\Office") ||
                keyExists(HKEY_LOCAL_MACHINE, L"SOFTWARE\\WPS Office");
  if (hasWps) brands.push_back("wps");

  return brands;
}

static bool SetRegString(HKEY root,
                         const std::wstring& subKey,
                         const wchar_t* valueName,
                         const std::wstring& data) {
  HKEY hKey = NULL;
  if (RegCreateKeyExW(root, subKey.c_str(), 0, NULL, REG_OPTION_NON_VOLATILE,
                      KEY_WRITE, NULL, &hKey, NULL) != ERROR_SUCCESS) {
    return false;
  }
  const bool ok =
      RegSetValueExW(hKey, valueName, 0, REG_SZ, (const BYTE*)data.c_str(),
                     (DWORD)((data.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
  RegCloseKey(hKey);
  return ok;
}

static std::wstring ProgIdForExtension(const std::wstring& ext) {
  std::wstring suffix = ext;
  if (!suffix.empty() && suffix[0] == L'.') {
    suffix = suffix.substr(1);
  }
  for (wchar_t& c : suffix) {
    if (c == L'.') {
      c = L'_';
    }
  }
  return L"CBFileHub.File." + suffix;
}

static bool RegisterFileAssociations(const std::string& exePathUtf8,
                                     const std::vector<std::string>& extensionsUtf8,
                                     bool setAsDefault) {
  if (exePathUtf8.empty() || extensionsUtf8.empty()) {
    return false;
  }

  int exeWide = MultiByteToWideChar(CP_UTF8, 0, exePathUtf8.c_str(), -1, nullptr, 0);
  if (exeWide == 0) {
    return false;
  }
  std::vector<wchar_t> wExe(exeWide);
  if (MultiByteToWideChar(CP_UTF8, 0, exePathUtf8.c_str(), -1, wExe.data(), exeWide) == 0) {
    return false;
  }
  const std::wstring exePath(wExe.data());

  size_t last = exePathUtf8.find_last_of("/\\");
  const std::string exeNameUtf8 =
      (last != std::string::npos) ? exePathUtf8.substr(last + 1) : exePathUtf8;
  if (exeNameUtf8.empty()) {
    return false;
  }
  int nameWide = MultiByteToWideChar(CP_UTF8, 0, exeNameUtf8.c_str(), -1, nullptr, 0);
  if (nameWide == 0) {
    return false;
  }
  std::vector<wchar_t> wName(nameWide);
  if (MultiByteToWideChar(CP_UTF8, 0, exeNameUtf8.c_str(), -1, wName.data(), nameWide) == 0) {
    return false;
  }
  const std::wstring exeName(wName.data());

  const std::wstring openCmd = L"\"" + exePath + L"\" \"%1\"";
  const std::wstring appProgId = L"Applications\\" + exeName;
  const std::wstring capsKey = L"Software\\COOLBIRDZIK\\CB File Hub\\Capabilities";

  if (!SetRegString(HKEY_CURRENT_USER,
                    L"Software\\Classes\\" + appProgId + L"\\shell\\open\\command",
                    NULL, openCmd)) {
    return false;
  }
  SetRegString(HKEY_CURRENT_USER, L"Software\\Classes\\" + appProgId,
               L"FriendlyAppName", L"CB File Hub");
  SetRegString(HKEY_CURRENT_USER, capsKey, L"ApplicationName", L"CB File Hub");
  SetRegString(HKEY_CURRENT_USER, capsKey, L"ApplicationDescription",
               L"CB File Hub file manager");

  bool any = false;
  for (const auto& extUtf8 : extensionsUtf8) {
    int extWide = MultiByteToWideChar(CP_UTF8, 0, extUtf8.c_str(), -1, nullptr, 0);
    if (extWide == 0) {
      continue;
    }
    std::vector<wchar_t> wExt(extWide);
    if (MultiByteToWideChar(CP_UTF8, 0, extUtf8.c_str(), -1, wExt.data(), extWide) == 0) {
      continue;
    }
    std::wstring ext(wExt.data());
    if (ext.empty()) {
      continue;
    }
    if (ext[0] != L'.') {
      ext = L"." + ext;
    }

    const std::wstring progId = ProgIdForExtension(ext);
    const std::wstring displayName = L"CB File Hub " + ext + L" File";
    const std::wstring progBase = L"Software\\Classes\\" + progId;

    SetRegString(HKEY_CURRENT_USER, progBase, NULL, displayName);
    SetRegString(HKEY_CURRENT_USER, progBase + L"\\shell\\open\\command", NULL, openCmd);
    SetRegString(HKEY_CURRENT_USER, progBase + L"\\DefaultIcon", NULL, exePath + L",0");
    SetRegString(HKEY_CURRENT_USER, L"Software\\Classes\\" + ext + L"\\OpenWithList",
                 exeName.c_str(), L"");
    SetRegString(HKEY_CURRENT_USER, L"Software\\Classes\\" + ext + L"\\OpenWithProgids",
                 progId.c_str(), L"");
    SetRegString(HKEY_CURRENT_USER, capsKey + L"\\FileAssociations", ext.c_str(), progId);

    if (setAsDefault) {
      SetRegString(HKEY_CURRENT_USER, L"Software\\Classes\\" + ext, NULL, progId);
    }
    any = true;
  }

  SetRegString(HKEY_CURRENT_USER, L"Software\\RegisteredApplications",
               L"CB File Hub", capsKey);
  return any;
}

static bool RegisterTorrentAssociations(const std::string& exePathUtf8) {
  // Capabilities advertise handlers; Windows owns the protected UserChoice.
  // Do not replace another client's magnet command or current defaults.
  if (!RegisterFileAssociations(exePathUtf8, {".torrent"}, false)) return false;
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                     exePathUtf8.c_str(), -1, nullptr, 0);
  if (size <= 0) return false;
  std::vector<wchar_t> wide(size);
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                          exePathUtf8.c_str(), -1, wide.data(), size)) return false;
  const std::wstring exe(wide.data());
  const std::wstring command = L"\"" + exe + L"\" --open-torrent \"%1\"";
  const std::wstring base = L"Software\\Classes\\CBFileHub.Magnet";
  const std::wstring caps = L"Software\\COOLBIRDZIK\\CB File Hub\\Capabilities";
  bool ok = SetRegString(HKEY_CURRENT_USER, base, nullptr, L"CB File Hub Magnet Link");
  ok = SetRegString(HKEY_CURRENT_USER, base, L"URL Protocol", L"") && ok;
  ok = SetRegString(HKEY_CURRENT_USER, base + L"\\DefaultIcon", nullptr,
                    L"\"" + exe + L"\",0") && ok;
  ok = SetRegString(HKEY_CURRENT_USER, base + L"\\shell\\open\\command",
                    nullptr, command) && ok;
  ok = SetRegString(HKEY_CURRENT_USER,
                    L"Software\\Classes\\CBFileHub.File.torrent\\shell\\open\\command",
                    nullptr, command) && ok;
  ok = SetRegString(HKEY_CURRENT_USER, L"Software\\Classes\\.torrent",
                    L"Content Type", L"application/x-bittorrent") && ok;
  ok = SetRegString(HKEY_CURRENT_USER, L"Software\\Classes\\magnet",
                    L"URL Protocol", L"") && ok;
  ok = SetRegString(HKEY_CURRENT_USER, caps + L"\\URLAssociations", L"magnet",
                    L"CBFileHub.Magnet") && ok;
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return ok;
}

static bool SetSelfAsDefaultForVideo(const std::string& exePath) {
  static const char* kVideoExts[] = {
      ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv", ".webm", ".m4v",
      ".mpeg", ".mpg", ".ogv", ".3gp", ".ts", ".m2ts", ".divx",
  };
  std::vector<std::string> extensions;
  extensions.reserve(sizeof(kVideoExts) / sizeof(kVideoExts[0]));
  for (const char* ext : kVideoExts) {
    extensions.emplace_back(ext);
  }
  return RegisterFileAssociations(exePath, extensions, true);
}

// ---------------------------------------------------------------------------
// Batch extract file-type icons by extension using SHGetFileInfo +
// SHGFI_USEFILEATTRIBUTES (no real file needed).
// ---------------------------------------------------------------------------
void AppIconPlugin::ExtractIconsForExtensions(
    const std::vector<std::string>& extensions,
    int iconSize,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  // We run the extraction synchronously on the platform thread since
  // SHGetFileInfo with USEFILEATTRIBUTES is fast (no disk I/O).
  flutter::EncodableMap responseMap;

  for (const auto& ext : extensions) {
    // Ensure extension starts with dot
    std::string dotExt = ext;
    if (!dotExt.empty() && dotExt[0] != '.') {
      dotExt = "." + dotExt;
    }

    // Convert to wide string
    int wideSize = MultiByteToWideChar(CP_UTF8, 0, dotExt.c_str(), -1, nullptr, 0);
    if (wideSize == 0) {
      responseMap[flutter::EncodableValue(ext)] = flutter::EncodableValue();
      continue;
    }
    std::vector<wchar_t> wExt(wideSize);
    if (MultiByteToWideChar(CP_UTF8, 0, dotExt.c_str(), -1, wExt.data(), wideSize) == 0) {
      responseMap[flutter::EncodableValue(ext)] = flutter::EncodableValue();
      continue;
    }

    // Use a fake filename with the extension — SHGFI_USEFILEATTRIBUTES means
    // the file doesn't need to exist.
    std::wstring fakeName = L"file" + std::wstring(wExt.data());

    SHFILEINFOW fileInfo = { 0 };
    UINT flags = SHGFI_ICON | SHGFI_USEFILEATTRIBUTES;
    flags |= (iconSize > 32) ? SHGFI_LARGEICON : SHGFI_LARGEICON;

    DWORD_PTR shResult = SHGetFileInfoW(
        fakeName.c_str(),
        FILE_ATTRIBUTE_NORMAL,
        &fileInfo,
        sizeof(fileInfo),
        flags
    );

    if (shResult == 0 || !fileInfo.hIcon) {
      responseMap[flutter::EncodableValue(ext)] = flutter::EncodableValue();
      continue;
    }

    // Get icon dimensions
    ICONINFO iconInfo;
    if (!GetIconInfo(fileInfo.hIcon, &iconInfo)) {
      DestroyIcon(fileInfo.hIcon);
      responseMap[flutter::EncodableValue(ext)] = flutter::EncodableValue();
      continue;
    }

    BITMAP bmp;
    if (!GetObject(iconInfo.hbmColor, sizeof(BITMAP), &bmp)) {
      DeleteObject(iconInfo.hbmMask);
      DeleteObject(iconInfo.hbmColor);
      DestroyIcon(fileInfo.hIcon);
      responseMap[flutter::EncodableValue(ext)] = flutter::EncodableValue();
      continue;
    }

    int w = bmp.bmWidth;
    int h = bmp.bmHeight;

    // Create memory DC and extract BGRA pixels
    HDC screenDC = GetDC(NULL);
    HDC memDC = CreateCompatibleDC(screenDC);
    HBITMAP hBitmap = CreateCompatibleBitmap(screenDC, w, h);
    HBITMAP oldBitmap = (HBITMAP)SelectObject(memDC, hBitmap);

    // Fill with transparent black
    HBRUSH hBrush = CreateSolidBrush(RGB(0, 0, 0));
    RECT rect = { 0, 0, w, h };
    FillRect(memDC, &rect, hBrush);
    DeleteObject(hBrush);

    // Draw icon
    DrawIconEx(memDC, 0, 0, fileInfo.hIcon, w, h, 0, NULL, DI_NORMAL);

    // Read pixels
    BITMAPINFOHEADER bmi = { 0 };
    bmi.biSize = sizeof(BITMAPINFOHEADER);
    bmi.biWidth = w;
    bmi.biHeight = -h; // top-down
    bmi.biPlanes = 1;
    bmi.biBitCount = 32;
    bmi.biCompression = BI_RGB;

    int stride = ((w * 32 + 31) / 32) * 4;
    int imageSize = stride * h;
    std::vector<uint8_t> pixels(imageSize);

    bool ok = (GetDIBits(memDC, hBitmap, 0, h, pixels.data(),
                         (BITMAPINFO*)&bmi, DIB_RGB_COLORS) != 0);

    // Cleanup GDI
    SelectObject(memDC, oldBitmap);
    DeleteObject(hBitmap);
    DeleteDC(memDC);
    ReleaseDC(NULL, screenDC);
    DeleteObject(iconInfo.hbmMask);
    DeleteObject(iconInfo.hbmColor);
    DestroyIcon(fileInfo.hIcon);

    if (ok) {
      // Return as map: {iconData: bytes, width: int, height: int}
      flutter::EncodableMap iconMap;
      iconMap[flutter::EncodableValue("iconData")] = flutter::EncodableValue(pixels);
      iconMap[flutter::EncodableValue("width")] = flutter::EncodableValue(w);
      iconMap[flutter::EncodableValue("height")] = flutter::EncodableValue(h);
      responseMap[flutter::EncodableValue(ext)] = flutter::EncodableValue(iconMap);
    } else {
      responseMap[flutter::EncodableValue(ext)] = flutter::EncodableValue();
    }
  }

  result->Success(flutter::EncodableValue(responseMap));
}
