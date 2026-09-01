#include "app_insights_plugin.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>
#include <winreg.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.ApplicationModel.Core.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Management.Deployment.h>
#include <winrt/Windows.Storage.h>
#include <winrt/base.h>

#include <algorithm>
#include <cstdint>
#include <ctime>
#include <iomanip>
#include <memory>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr wchar_t kUninstallKey[] =
    L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall";
constexpr wchar_t kUserAssistKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\UserAssist";

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  const int required = WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (required <= 0) return std::string();
  std::string converted(static_cast<size_t>(required), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), converted.data(),
                      required, nullptr, nullptr);
  return converted;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int required = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (required <= 0) return std::wstring();
  std::wstring converted(static_cast<size_t>(required), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), converted.data(),
                      required);
  return converted;
}

void AddString(EncodableMap* map, const char* key, const std::wstring& value) {
  if (value.empty()) return;
  (*map)[EncodableValue(key)] = EncodableValue(WideToUtf8(value));
}

std::string FormatIsoUtc(
    const winrt::Windows::Foundation::DateTime& date_time) {
  const std::time_t timestamp = winrt::clock::to_time_t(date_time);
  if (timestamp <= 0) return std::string();
  std::tm utc_time{};
  if (gmtime_s(&utc_time, &timestamp) != 0) return std::string();
  std::ostringstream formatted;
  formatted << std::put_time(&utc_time, "%Y-%m-%dT%H:%M:%SZ");
  return formatted.str();
}

std::wstring ReadRegistryString(HKEY key, const wchar_t* value_name) {
  DWORD type = 0;
  DWORD byte_count = 0;
  if (RegQueryValueExW(key, value_name, nullptr, &type, nullptr, &byte_count) !=
          ERROR_SUCCESS ||
      (type != REG_SZ && type != REG_EXPAND_SZ) || byte_count == 0) {
    return std::wstring();
  }

  std::vector<wchar_t> buffer(
      static_cast<size_t>(byte_count / sizeof(wchar_t)) + 1, L'\0');
  if (RegQueryValueExW(key, value_name, nullptr, &type,
                       reinterpret_cast<LPBYTE>(buffer.data()),
                       &byte_count) != ERROR_SUCCESS) {
    return std::wstring();
  }
  std::wstring value(buffer.data());
  if (type != REG_EXPAND_SZ || value.empty()) return value;

  const DWORD expanded_count =
      ExpandEnvironmentStringsW(value.c_str(), nullptr, 0);
  if (expanded_count == 0) return value;
  std::vector<wchar_t> expanded(static_cast<size_t>(expanded_count), L'\0');
  if (ExpandEnvironmentStringsW(value.c_str(), expanded.data(),
                                expanded_count) == 0) {
    return value;
  }
  return std::wstring(expanded.data());
}

bool ReadRegistryInteger(HKEY key, const wchar_t* value_name,
                         int64_t* output) {
  DWORD type = 0;
  DWORD byte_count = 0;
  if (RegQueryValueExW(key, value_name, nullptr, &type, nullptr, &byte_count) !=
      ERROR_SUCCESS) {
    return false;
  }
  if (type == REG_DWORD && byte_count == sizeof(DWORD)) {
    DWORD value = 0;
    if (RegQueryValueExW(key, value_name, nullptr, &type,
                         reinterpret_cast<LPBYTE>(&value),
                         &byte_count) == ERROR_SUCCESS) {
      *output = static_cast<int64_t>(value);
      return true;
    }
  }
  if (type == REG_QWORD && byte_count == sizeof(ULONGLONG)) {
    ULONGLONG value = 0;
    if (RegQueryValueExW(key, value_name, nullptr, &type,
                         reinterpret_cast<LPBYTE>(&value),
                         &byte_count) == ERROR_SUCCESS) {
      *output = static_cast<int64_t>(value);
      return true;
    }
  }
  return false;
}

void AddRegistryInteger(EncodableMap* map, const char* key, HKEY registry_key,
                        const wchar_t* value_name) {
  int64_t value = 0;
  if (ReadRegistryInteger(registry_key, value_name, &value)) {
    (*map)[EncodableValue(key)] = EncodableValue(value);
  }
}

void AppendRegistryWarning(EncodableList* warnings, const std::string& label,
                           LSTATUS status) {
  std::ostringstream message;
  message << label << " (Windows error " << status << ")";
  warnings->push_back(EncodableValue(message.str()));
}

void ReadUninstallView(HKEY root, const char* root_name, REGSAM view,
                       const char* view_name, EncodableList* records,
                       EncodableList* warnings, bool* is_partial) {
  HKEY uninstall_key = nullptr;
  const LSTATUS open_status =
      RegOpenKeyExW(root, kUninstallKey, 0, KEY_READ | view, &uninstall_key);
  if (open_status == ERROR_FILE_NOT_FOUND) return;
  if (open_status != ERROR_SUCCESS) {
    AppendRegistryWarning(warnings,
                          std::string("Could not open ") + root_name + " " +
                              view_name + "-bit uninstall registry",
                          open_status);
    *is_partial = true;
    return;
  }

  DWORD max_subkey_length = 255;
  RegQueryInfoKeyW(uninstall_key, nullptr, nullptr, nullptr, nullptr,
                   &max_subkey_length, nullptr, nullptr, nullptr, nullptr,
                   nullptr, nullptr);
  std::vector<wchar_t> key_name(
      static_cast<size_t>(max_subkey_length) + 2, L'\0');

  for (DWORD index = 0;; ++index) {
    DWORD key_name_length = static_cast<DWORD>(key_name.size() - 1);
    const LSTATUS enum_status =
        RegEnumKeyExW(uninstall_key, index, key_name.data(), &key_name_length,
                      nullptr, nullptr, nullptr, nullptr);
    if (enum_status == ERROR_NO_MORE_ITEMS) break;
    if (enum_status != ERROR_SUCCESS) {
      AppendRegistryWarning(warnings, "Could not enumerate uninstall entry",
                            enum_status);
      *is_partial = true;
      continue;
    }
    key_name[key_name_length] = L'\0';

    HKEY app_key = nullptr;
    const LSTATUS app_status =
        RegOpenKeyExW(uninstall_key, key_name.data(), 0, KEY_READ | view,
                      &app_key);
    if (app_status != ERROR_SUCCESS) {
      if (app_status == ERROR_ACCESS_DENIED) *is_partial = true;
      continue;
    }

    EncodableMap record;
    record[EncodableValue("registryRoot")] = EncodableValue(root_name);
    record[EncodableValue("registryView")] = EncodableValue(view_name);
    record[EncodableValue("registryKeyName")] =
        EncodableValue(WideToUtf8(std::wstring(key_name.data())));
    AddString(&record, "displayName",
              ReadRegistryString(app_key, L"DisplayName"));
    AddString(&record, "publisher",
              ReadRegistryString(app_key, L"Publisher"));
    AddString(&record, "displayVersion",
              ReadRegistryString(app_key, L"DisplayVersion"));
    AddString(&record, "installLocation",
              ReadRegistryString(app_key, L"InstallLocation"));
    AddString(&record, "displayIcon",
              ReadRegistryString(app_key, L"DisplayIcon"));
    AddString(&record, "uninstallString",
              ReadRegistryString(app_key, L"UninstallString"));
    AddString(&record, "quietUninstallString",
              ReadRegistryString(app_key, L"QuietUninstallString"));
    AddString(&record, "parentKeyName",
              ReadRegistryString(app_key, L"ParentKeyName"));
    AddString(&record, "releaseType",
              ReadRegistryString(app_key, L"ReleaseType"));
    AddString(&record, "installDate",
              ReadRegistryString(app_key, L"InstallDate"));
    AddRegistryInteger(&record, "estimatedSizeKb", app_key,
                       L"EstimatedSize");
    AddRegistryInteger(&record, "systemComponent", app_key,
                       L"SystemComponent");
    AddRegistryInteger(&record, "noDisplay", app_key, L"NoDisplay");
    records->push_back(EncodableValue(record));
    RegCloseKey(app_key);
  }

  RegCloseKey(uninstall_key);
}

EncodableValue ReadWin32UninstallEntries() {
  EncodableList records;
  EncodableList warnings;
  bool is_partial = false;
  for (const auto& root :
       std::vector<std::pair<HKEY, const char*>>{{HKEY_LOCAL_MACHINE, "HKLM"},
                                                 {HKEY_CURRENT_USER, "HKCU"}}) {
    ReadUninstallView(root.first, root.second, KEY_WOW64_64KEY, "64", &records,
                      &warnings, &is_partial);
    ReadUninstallView(root.first, root.second, KEY_WOW64_32KEY, "32", &records,
                      &warnings, &is_partial);
  }
  return EncodableValue(EncodableMap{
      {EncodableValue("records"), EncodableValue(records)},
      {EncodableValue("warnings"), EncodableValue(warnings)},
      {EncodableValue("isPartial"), EncodableValue(is_partial)},
  });
}

EncodableValue ReadUserAssist() {
  EncodableList records;
  EncodableList warnings;
  bool is_partial = false;
  HKEY user_assist_key = nullptr;
  const LSTATUS root_status = RegOpenKeyExW(
      HKEY_CURRENT_USER, kUserAssistKey, 0, KEY_READ, &user_assist_key);
  if (root_status == ERROR_FILE_NOT_FOUND) {
    return EncodableValue(EncodableMap{
        {EncodableValue("records"), EncodableValue(records)},
        {EncodableValue("warnings"), EncodableValue(warnings)},
        {EncodableValue("isPartial"), EncodableValue(false)},
    });
  }
  if (root_status != ERROR_SUCCESS) {
    AppendRegistryWarning(&warnings, "Could not open UserAssist registry",
                          root_status);
    return EncodableValue(EncodableMap{
        {EncodableValue("records"), EncodableValue(records)},
        {EncodableValue("warnings"), EncodableValue(warnings)},
        {EncodableValue("isPartial"), EncodableValue(true)},
    });
  }

  DWORD max_subkey_length = 255;
  RegQueryInfoKeyW(user_assist_key, nullptr, nullptr, nullptr, nullptr,
                   &max_subkey_length, nullptr, nullptr, nullptr, nullptr,
                   nullptr, nullptr);
  std::vector<wchar_t> guid_name(
      static_cast<size_t>(max_subkey_length) + 2, L'\0');

  for (DWORD index = 0;; ++index) {
    DWORD guid_length = static_cast<DWORD>(guid_name.size() - 1);
    const LSTATUS enum_status =
        RegEnumKeyExW(user_assist_key, index, guid_name.data(), &guid_length,
                      nullptr, nullptr, nullptr, nullptr);
    if (enum_status == ERROR_NO_MORE_ITEMS) break;
    if (enum_status != ERROR_SUCCESS) {
      is_partial = true;
      continue;
    }
    guid_name[guid_length] = L'\0';
    const std::wstring count_path =
        std::wstring(guid_name.data()) + L"\\Count";
    HKEY count_key = nullptr;
    const LSTATUS count_status = RegOpenKeyExW(
        user_assist_key, count_path.c_str(), 0, KEY_READ, &count_key);
    if (count_status == ERROR_FILE_NOT_FOUND) continue;
    if (count_status != ERROR_SUCCESS) {
      if (count_status == ERROR_ACCESS_DENIED) is_partial = true;
      continue;
    }

    DWORD max_value_name = 1024;
    DWORD max_value_data = 72;
    RegQueryInfoKeyW(count_key, nullptr, nullptr, nullptr, nullptr, nullptr,
                     nullptr, nullptr, &max_value_name, &max_value_data,
                     nullptr, nullptr);
    std::vector<wchar_t> value_name(
        static_cast<size_t>(max_value_name) + 2, L'\0');
    std::vector<uint8_t> value_data(
        std::max<size_t>(static_cast<size_t>(max_value_data), 72));

    for (DWORD value_index = 0;; ++value_index) {
      DWORD value_name_length = static_cast<DWORD>(value_name.size() - 1);
      DWORD data_length = static_cast<DWORD>(value_data.size());
      DWORD type = 0;
      const LSTATUS value_status = RegEnumValueW(
          count_key, value_index, value_name.data(), &value_name_length,
          nullptr, &type, value_data.data(), &data_length);
      if (value_status == ERROR_NO_MORE_ITEMS) break;
      if (value_status != ERROR_SUCCESS) {
        is_partial = true;
        continue;
      }
      if (type != REG_BINARY || data_length == 0) continue;
      value_name[value_name_length] = L'\0';
      std::vector<uint8_t> bytes(value_data.begin(),
                                 value_data.begin() + data_length);
      records.push_back(EncodableValue(EncodableMap{
          {EncodableValue("encodedName"),
           EncodableValue(WideToUtf8(std::wstring(value_name.data())))},
          {EncodableValue("data"), EncodableValue(bytes)},
      }));
    }
    RegCloseKey(count_key);
  }

  RegCloseKey(user_assist_key);
  return EncodableValue(EncodableMap{
      {EncodableValue("records"), EncodableValue(records)},
      {EncodableValue("warnings"), EncodableValue(warnings)},
      {EncodableValue("isPartial"), EncodableValue(is_partial)},
  });
}

std::wstring ExpandEnvironmentPath(const std::wstring& value) {
  const DWORD required = ExpandEnvironmentStringsW(value.c_str(), nullptr, 0);
  if (required == 0) return value;
  std::vector<wchar_t> buffer(static_cast<size_t>(required), L'\0');
  if (ExpandEnvironmentStringsW(value.c_str(), buffer.data(), required) == 0) {
    return value;
  }
  return std::wstring(buffer.data());
}

std::wstring ExpandKnownFolderPath(const std::wstring& input) {
  const size_t open_brace = input.find(L'{');
  if (open_brace == std::wstring::npos) return input;
  const size_t close_brace = input.find(L'}', open_brace + 1);
  if (close_brace == std::wstring::npos) return input;
  const std::wstring guid_text =
      input.substr(open_brace, close_brace - open_brace + 1);
  GUID folder_id{};
  if (FAILED(CLSIDFromString(guid_text.c_str(), &folder_id))) return input;

  PWSTR known_folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr,
                                  &known_folder)) ||
      known_folder == nullptr) {
    return input;
  }
  std::wstring expanded(known_folder);
  CoTaskMemFree(known_folder);
  std::wstring suffix = input.substr(close_brace + 1);
  while (!suffix.empty() &&
         (suffix.front() == L'\\' || suffix.front() == L'/')) {
    suffix.erase(suffix.begin());
  }
  if (!suffix.empty()) {
    if (!expanded.empty() && expanded.back() != L'\\') expanded.push_back(L'\\');
    expanded.append(suffix);
  }
  return expanded;
}

std::wstring ResolveShortcut(const std::wstring& path) {
  if (path.size() < 4 || _wcsicmp(path.c_str() + path.size() - 4, L".lnk") != 0) {
    return path;
  }
  IShellLinkW* shell_link = nullptr;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_IShellLinkW,
                              reinterpret_cast<void**>(&shell_link))) ||
      shell_link == nullptr) {
    return path;
  }
  IPersistFile* persist_file = nullptr;
  if (FAILED(shell_link->QueryInterface(IID_IPersistFile,
                                        reinterpret_cast<void**>(&persist_file))) ||
      persist_file == nullptr) {
    shell_link->Release();
    return path;
  }

  std::wstring resolved = path;
  if (SUCCEEDED(persist_file->Load(path.c_str(), STGM_READ))) {
    shell_link->Resolve(nullptr, SLR_NO_UI | SLR_NOSEARCH | SLR_NOTRACK);
    std::vector<wchar_t> target(32768, L'\0');
    WIN32_FIND_DATAW find_data{};
    if (SUCCEEDED(shell_link->GetPath(target.data(),
                                      static_cast<int>(target.size()),
                                      &find_data, SLGP_RAWPATH)) &&
        target.front() != L'\0') {
      resolved.assign(target.data());
    }
  }
  persist_file->Release();
  shell_link->Release();
  return resolved;
}

EncodableValue ResolveUserAssistTargets(const EncodableValue* arguments) {
  EncodableMap response;
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) return EncodableValue(response);
  const auto target_it = map->find(EncodableValue("targets"));
  if (target_it == map->end()) return EncodableValue(response);
  const auto* targets = std::get_if<EncodableList>(&target_it->second);
  if (targets == nullptr) return EncodableValue(response);

  const HRESULT com_status =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool uninitialize = SUCCEEDED(com_status);
  for (const EncodableValue& target_value : *targets) {
    const auto* encoded = std::get_if<std::string>(&target_value);
    if (encoded == nullptr || encoded->empty()) continue;
    const std::wstring original = Utf8ToWide(*encoded);
    std::wstring resolved = ExpandEnvironmentPath(original);
    resolved = ExpandKnownFolderPath(resolved);
    resolved = ResolveShortcut(resolved);
    response[EncodableValue(*encoded)] = EncodableValue(WideToUtf8(resolved));
  }
  if (uninitialize) CoUninitialize();
  return EncodableValue(response);
}

EncodableValue ReadMsixPackages() {
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  EncodableList records;
  EncodableList warnings;
  winrt::Windows::Management::Deployment::PackageManager package_manager;

  for (const auto& package : package_manager.FindPackagesForUser(L"")) {
    if (package.IsFramework() || package.IsResourcePackage()) continue;
    const auto app_entries = package.GetAppListEntriesAsync().get();
    if (app_entries.Size() == 0) continue;

    const auto package_id = package.Id();
    const auto version = package_id.Version();
    std::ostringstream version_text;
    version_text << version.Major << "." << version.Minor << "."
                 << version.Build << "." << version.Revision;
    EncodableList app_user_model_ids;
    for (const auto& app_entry : app_entries) {
      app_user_model_ids.push_back(
          EncodableValue(WideToUtf8(app_entry.AppUserModelId().c_str())));
    }

    EncodableMap record;
    record[EncodableValue("packageName")] =
        EncodableValue(WideToUtf8(package_id.Name().c_str()));
    record[EncodableValue("packageFamilyName")] =
        EncodableValue(WideToUtf8(package_id.FamilyName().c_str()));
    record[EncodableValue("packageFullName")] =
        EncodableValue(WideToUtf8(package_id.FullName().c_str()));
    record[EncodableValue("displayName")] =
        EncodableValue(WideToUtf8(package.DisplayName().c_str()));
    record[EncodableValue("publisher")] =
        EncodableValue(WideToUtf8(package_id.Publisher().c_str()));
    record[EncodableValue("publisherDisplayName")] =
        EncodableValue(WideToUtf8(package.PublisherDisplayName().c_str()));
    record[EncodableValue("version")] = EncodableValue(version_text.str());
    record[EncodableValue("installLocation")] = EncodableValue(
        WideToUtf8(package.InstalledLocation().Path().c_str()));
    try {
      const std::string installed_date = FormatIsoUtc(package.InstalledDate());
      if (!installed_date.empty()) {
        record[EncodableValue("installedDate")] =
            EncodableValue(installed_date);
      }
    } catch (const winrt::hresult_error&) {
      // InstalledDate is optional on older package contracts.
    }
    record[EncodableValue("isFramework")] =
        EncodableValue(package.IsFramework());
    record[EncodableValue("isResourcePackage")] =
        EncodableValue(package.IsResourcePackage());
    record[EncodableValue("isLaunchable")] = EncodableValue(true);
    record[EncodableValue("appUserModelIds")] =
        EncodableValue(app_user_model_ids);
    records.push_back(EncodableValue(record));
  }

  return EncodableValue(EncodableMap{
      {EncodableValue("records"), EncodableValue(records)},
      {EncodableValue("warnings"), EncodableValue(warnings)},
      {EncodableValue("isPartial"), EncodableValue(false)},
  });
}

}  // namespace

void AppInsightsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "cb_file_manager/app_insights",
      &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<AppInsightsPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

AppInsightsPlugin::AppInsightsPlugin() = default;
AppInsightsPlugin::~AppInsightsPlugin() = default;

void AppInsightsPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (method_call.method_name() == "readWin32UninstallEntries") {
    result->Success(ReadWin32UninstallEntries());
    return;
  }
  if (method_call.method_name() == "readUserAssist") {
    result->Success(ReadUserAssist());
    return;
  }
  if (method_call.method_name() == "resolveUserAssistTargets") {
    result->Success(ResolveUserAssistTargets(method_call.arguments()));
    return;
  }
  if (method_call.method_name() == "readMsixPackages") {
    auto* result_pointer = result.release();
    std::thread([result_pointer]() {
      std::unique_ptr<flutter::MethodResult<EncodableValue>> thread_result(
          result_pointer);
      try {
        thread_result->Success(ReadMsixPackages());
      } catch (const winrt::hresult_error& error) {
        thread_result->Error("PACKAGE_MANAGER_FAILED",
                             WideToUtf8(error.message().c_str()));
      } catch (...) {
        thread_result->Error("PACKAGE_MANAGER_FAILED",
                             "Windows PackageManager returned an unknown error.");
      }
    }).detach();
    return;
  }
  result->NotImplemented();
}
