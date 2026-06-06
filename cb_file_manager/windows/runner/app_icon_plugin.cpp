#include "app_icon_plugin.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <commctrl.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <shellapi.h>
#include <shobjidl.h>
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

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ole32.lib")

static std::string ParseExeFromCommand(const wchar_t* cmd);
static std::string ResolveExeViaApplicationsKey(const std::string& exeName);
static std::string ResolveProgIdToExe(const std::wstring& progId);

static bool SetSelfAsDefaultForVideo(const std::string& exePath);
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
    : registrar_(registrar) {}

AppIconPlugin::~AppIconPlugin() {}

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

  // Get executable path for this file extension
  wchar_t execPath[MAX_PATH] = { 0 };
  DWORD execPathSize = MAX_PATH;

  HRESULT hr = AssocQueryStringW(
      ASSOCF_NONE,
      ASSOCSTR_EXECUTABLE,
      wExtension.data(),
      NULL,
      execPath,
      &execPathSize
  );

  if (FAILED(hr)) {
    return "";
  }

  // Convert result to UTF-8
  int utf8Size = WideCharToMultiByte(CP_UTF8, 0, execPath, -1, nullptr, 0, NULL, NULL);
  if (utf8Size == 0) {
    return "";
  }
  
  std::vector<char> utf8Path(utf8Size);
  if (WideCharToMultiByte(CP_UTF8, 0, execPath, -1, utf8Path.data(), utf8Size, NULL, NULL) == 0) {
    return "";
  }
  
  return std::string(utf8Path.data());
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

static bool SetSelfAsDefaultForVideo(const std::string& exePath) {
  if (exePath.empty()) return false;
  size_t last = exePath.find_last_of("/\\");
  std::string exeName = (last != std::string::npos) ? exePath.substr(last + 1) : exePath;
  if (exeName.empty()) return false;

  int exeWide = MultiByteToWideChar(CP_UTF8, 0, exePath.c_str(), -1, nullptr, 0);
  if (exeWide == 0) return false;
  std::vector<wchar_t> wExe(exeWide);
  if (MultiByteToWideChar(CP_UTF8, 0, exePath.c_str(), -1, wExe.data(), exeWide) == 0) return false;

  int nameWide = MultiByteToWideChar(CP_UTF8, 0, exeName.c_str(), -1, nullptr, 0);
  if (nameWide == 0) return false;
  std::vector<wchar_t> wName(nameWide);
  if (MultiByteToWideChar(CP_UTF8, 0, exeName.c_str(), -1, wName.data(), nameWide) == 0) return false;

  std::wstring cmdVal = L"\"" + std::wstring(wExe.data()) + L"\" \"%1\"";
  std::wstring appProgId = L"Applications\\" + std::wstring(wName.data());

  std::wstring cmdKey = L"SOFTWARE\\Classes\\" + appProgId + L"\\shell\\open\\command";
  HKEY hCmd = NULL;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, cmdKey.c_str(), 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hCmd, NULL) != ERROR_SUCCESS)
    return false;
  bool ok = (RegSetValueExW(hCmd, NULL, 0, REG_SZ, (const BYTE*)cmdVal.c_str(), (DWORD)((cmdVal.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS);
  RegCloseKey(hCmd);
  if (!ok) return false;

  static const wchar_t* videoExts[] = {
    L".mp4", L".mkv", L".avi", L".mov", L".wmv", L".flv", L".webm", L".m4v",
    L".mpeg", L".mpg", L".ogv", L".3gp", L".ts", L".m2ts", L".divx"
  };
  for (const wchar_t* ext : videoExts) {
    std::wstring extKey = std::wstring(L"SOFTWARE\\Classes\\") + ext;
    HKEY hExt = NULL;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, extKey.c_str(), 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hExt, NULL) == ERROR_SUCCESS) {
      RegSetValueExW(hExt, NULL, 0, REG_SZ, (const BYTE*)appProgId.c_str(), (DWORD)((appProgId.size() + 1) * sizeof(wchar_t)));
      RegCloseKey(hExt);
    }
  }
  return true;
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