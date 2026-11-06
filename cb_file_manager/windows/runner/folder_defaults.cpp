#include "folder_defaults.h"
#include <appmodel.h>

#include <shlobj.h>
#include <stdexcept>
#include <vector>
#include <utility>

namespace folder_defaults {
namespace {
struct Value {
  bool exists = false;
  DWORD type = REG_NONE;
  std::vector<BYTE> bytes;
};
struct Change {
  std::wstring path;
  std::wstring name;
  std::wstring text;
};
class Key {
 public:
  HKEY value = nullptr;
  ~Key() { if (value) RegCloseKey(value); }
};
void Check(LSTATUS error) {
  if (error != ERROR_SUCCESS) {
    throw std::runtime_error("Registry operation failed (" + std::to_string(error) + ")");
  }
}
Value Read(const std::wstring& path, const std::wstring& name) {
  Key key;
  const auto opened = RegOpenKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, KEY_QUERY_VALUE, &key.value);
  if (opened == ERROR_FILE_NOT_FOUND || opened == ERROR_PATH_NOT_FOUND) return {};
  Check(opened);
  Value result;
  DWORD size = 0;
  auto status = RegQueryValueExW(key.value, name.c_str(), nullptr, &result.type, nullptr, &size);
  if (status == ERROR_FILE_NOT_FOUND) return {};
  Check(status);
  result.bytes.resize(size);
  Check(RegQueryValueExW(key.value, name.c_str(), nullptr, &result.type,
                         result.bytes.data(), &size));
  result.bytes.resize(size);
  result.exists = true;
  return result;
}
void Write(const std::wstring& path, const std::wstring& name, const Value& value) {
  Key key;
  if (!value.exists) {
    const auto opened = RegOpenKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, KEY_SET_VALUE, &key.value);
    if (opened == ERROR_FILE_NOT_FOUND || opened == ERROR_PATH_NOT_FOUND) return;
    Check(opened);
    const auto status = RegDeleteValueW(key.value, name.c_str());
    if (status != ERROR_FILE_NOT_FOUND) Check(status);
    return;
  }
  Check(RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0,
                         KEY_SET_VALUE, nullptr, &key.value, nullptr));
  Check(RegSetValueExW(key.value, name.c_str(), 0, value.type, value.bytes.data(),
                       static_cast<DWORD>(value.bytes.size())));
}
Value Text(const std::wstring& text) {
  const auto* start = reinterpret_cast<const BYTE*>(text.c_str());
  return {true, REG_SZ, std::vector<BYTE>(start, start + (text.size() + 1) * sizeof(wchar_t))};
}
std::wstring AsText(const Value& value) {
  if (!value.exists || value.type != REG_SZ || value.bytes.size() < sizeof(wchar_t) ||
      value.bytes.size() % sizeof(wchar_t) != 0) return {};
  const auto* data = reinterpret_cast<const wchar_t*>(value.bytes.data());
  if (data[value.bytes.size() / sizeof(wchar_t) - 1] != 0) return {};
  return std::wstring(data, value.bytes.size() / sizeof(wchar_t) - 1);
}
bool Equal(const Value& a, const Value& b) {
  return a.exists == b.exists && (!a.exists || (a.type == b.type && a.bytes == b.bytes));
}
// Only filesystem folder/drive verbs are redirected. Generic virtual Folder
// verbs remain Explorer-owned. The CLSID is Explorer's Win+E entry point.
std::vector<Change> Changes(const std::wstring& root, const std::wstring& executable) {
  const auto command = L"\"" + executable + L"\" --open-folder \"%1\\.\"";
  std::vector<Change> changes;
  for (const auto* type : {L"Directory", L"Drive"}) {
    const auto shell = root + L"\\" + type + L"\\shell";
    changes.push_back({shell, L"", L"open"});
    changes.push_back({shell + L"\\open\\command", L"", command});
    changes.push_back({shell + L"\\open\\command", L"DelegateExecute", L""});
  }
  const auto entry = root + L"\\CLSID\\{52205fd8-5dfb-447d-801a-d0b52f2e83e1}\\shell\\opennewwindow\\command";
  changes.push_back({entry, L"", L"\"" + executable + L"\" --open-folder"});
  changes.push_back({entry, L"DelegateExecute", L""});
  return changes;
}
void Notify() { SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr); }

// No recursive deletion of Shell keys. Remove only empty keys we created.
void Prune(std::wstring path, const std::wstring& stop) {
  while (path.size() > stop.size()) {
    Key key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, KEY_READ, &key.value) != ERROR_SUCCESS) return;
    DWORD subkeys = 0, values = 0;
    Check(RegQueryInfoKeyW(key.value, nullptr, nullptr, nullptr, &subkeys, nullptr,
                           nullptr, &values, nullptr, nullptr, nullptr, nullptr));
    if (subkeys || values) return;
    RegCloseKey(key.value);
    key.value = nullptr;
    Check(RegDeleteKeyW(HKEY_CURRENT_USER, path.c_str()));
    const auto separator = path.find_last_of(L'\\');
    if (separator == std::wstring::npos) return;
    path.resize(separator);
  }
}
class Lock {
 public:
  Lock() {
    handle_ = CreateMutexW(nullptr, FALSE, L"Local\\CBFileHubFolderDefaults");
    if (!handle_) throw std::runtime_error("Cannot lock folder defaults");
    const auto result = WaitForSingleObject(handle_, 5000);
    if (result != WAIT_OBJECT_0 && result != WAIT_ABANDONED) {
      CloseHandle(handle_);
      throw std::runtime_error("Folder defaults are being changed in another window");
    }
  }
  ~Lock() { ReleaseMutex(handle_); CloseHandle(handle_); }
 private:
  HANDLE handle_ = nullptr;
};
}  // namespace

Registration::Registration(std::wstring classes, std::wstring backup,
                           std::function<void(size_t)> before_change)
    : classes_(std::move(classes)), backup_(std::move(backup)),
      before_change_(std::move(before_change)) {}

std::wstring ExecutablePath() {
  std::wstring path(32768, L'\0');
  const auto size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) throw std::runtime_error("Cannot locate application");
  path.resize(size);
  return path;
}

Status Registration::Query(const std::wstring& executable) const {
  Status result;
  UINT32 package_length = 0;
  result.available = GetCurrentPackageFullName(&package_length, nullptr) == APPMODEL_ERROR_NO_PACKAGE;
  size_t matching = 0;
  const auto changes = Changes(classes_, executable);
  for (const auto& change : changes) {
    if (Equal(Read(change.path, change.name), Text(change.text))) ++matching;
  }
  result.enabled = matching == changes.size();
  // Empty DelegateExecute values alone are not evidence of our registration.
  result.partial = !result.enabled && matching > 0 &&
      AsText(Read(backup_, L"Executable")) == executable;
  result.can_restore = Read(backup_, L"Executable").exists;
  return result;
}

void Registration::Enable(const std::wstring& executable) {
  Lock lock;
  UINT32 length = 0;
  if (GetCurrentPackageFullName(&length, nullptr) != APPMODEL_ERROR_NO_PACKAGE) {
    throw std::runtime_error("Explorer redirection is available in unpackaged desktop builds only");
  }
  if (Query(executable).enabled) return;
  if (Read(backup_, L"Executable").exists) {
    throw std::runtime_error("Restore the previous registration before enabling again");
  }
  if (GetFileAttributesW(executable.c_str()) == INVALID_FILE_ATTRIBUTES) {
    throw std::runtime_error("Application executable is unavailable");
  }
  const auto changes = Changes(classes_, executable);
  // Persist a complete journal before touching associations. Each value keeps
  // its exact registry type and bytes, including absent vs empty values.
  for (size_t i = 0; i < changes.size(); ++i) {
    const auto saved = backup_ + L"\\" + std::to_wstring(i);
    const auto original = Read(changes[i].path, changes[i].name);
    Write(saved, L"Exists", Text(original.exists ? L"1" : L"0"));
    if (original.exists) Write(saved, L"Original", original);
    Write(saved, L"Installed", Text(changes[i].text));
    // Remember where pruning stops: never remove a pre-existing empty key.
    auto ancestor = changes[i].path;
    while (ancestor.size() > classes_.size()) {
      Key key;
      const auto status = RegOpenKeyExW(HKEY_CURRENT_USER, ancestor.c_str(), 0, KEY_READ, &key.value);
      if (status == ERROR_SUCCESS) break;
      if (status != ERROR_FILE_NOT_FOUND && status != ERROR_PATH_NOT_FOUND) Check(status);
      ancestor.resize(ancestor.find_last_of(L'\\'));
    }
    Write(saved, L"Ancestor", Text(ancestor));
  }
  Write(backup_, L"Phase", Text(L"installing"));
  Write(backup_, L"Executable", Text(executable));
  { Key key; Check(RegOpenKeyExW(HKEY_CURRENT_USER, backup_.c_str(), 0, KEY_READ, &key.value)); Check(RegFlushKey(key.value)); }
  try {
    for (size_t i = 0; i < changes.size(); ++i) {
      if (before_change_) before_change_(i);
      Write(changes[i].path, changes[i].name, Text(changes[i].text));
    }
    Write(backup_, L"Phase", Text(L"active"));
    Notify();
  } catch (...) {
    // Restore uses the journal and checks ownership; release the lock first
    // through a separate scope in the caller is unnecessary for same-thread
    // recursive Win32 mutex ownership.
    Restore();
    throw;
  }
}

void Registration::Restore(const std::wstring& expected_executable) {
  Lock lock;
  const auto executable = AsText(Read(backup_, L"Executable"));
  if (executable.empty()) return;
  if (!expected_executable.empty() && _wcsicmp(executable.c_str(), expected_executable.c_str()) != 0) return;
  const auto changes = Changes(classes_, executable);
  if (AsText(Read(backup_, L"Restoring")) != L"1") {
    // Capture ownership for the whole journal before restoring any command.
    // A restart during restore must not mistake our restored command for a
    // third-party takeover and strand its parent shell default.
    for (size_t i = 0; i < changes.size(); ++i) {
      const auto& change = changes[i];
      const auto saved = backup_ + L"\\" + std::to_wstring(i);
      bool owned = Equal(Read(change.path, change.name), Read(saved, L"Installed"));
      if (change.name == L"DelegateExecute") {
        owned = owned && Equal(Read(change.path, L""), Text(changes[i - 1].text));
      } else if (change.text == L"open") {
        const auto command_saved = backup_ + L"\\" + std::to_wstring(i + 1);
        const auto original = AsText(Read(command_saved, L"Exists")) == L"1"
            ? Read(command_saved, L"Original") : Value{};
        const auto command = Read(changes[i + 1].path, L"");
        // A failed enable can stop after writing the shell default, before
        // its command. That parent still belongs to our partial transaction.
        owned = owned && (Equal(command, Text(changes[i + 1].text)) ||
            (AsText(Read(backup_, L"Phase")) == L"installing" && Equal(command, original)));
      }
      Write(saved, L"Owned", Text(owned ? L"1" : L"0"));
    }
    Write(backup_, L"Restoring", Text(L"1"));
  }
  // Group ownership by verb command: a later application's DelegateExecute or
  // shell default must not be overwritten just because its bytes match ours.
  for (size_t i = changes.size(); i-- > 0;) {
    const auto& change = changes[i];
    const auto saved = backup_ + L"\\" + std::to_wstring(i);
    if (!Read(saved, L"Exists").exists) throw std::runtime_error("Folder default backup is incomplete");
    bool owned = AsText(Read(saved, L"Owned")) == L"1" &&
        Equal(Read(change.path, change.name), Read(saved, L"Installed"));
    if (change.name == L"DelegateExecute") {
      owned = owned && Equal(Read(change.path, L""), Text(changes[i - 1].text));
    } else if (change.text == L"open") {
      const auto command_saved = backup_ + L"\\" + std::to_wstring(i + 1);
      const auto current_command = Read(changes[i + 1].path, L"");
      const auto original_command = AsText(Read(command_saved, L"Exists")) == L"1"
          ? Read(command_saved, L"Original") : Value{};
      owned = owned && (Equal(current_command, Text(changes[i + 1].text)) ||
                         Equal(current_command, original_command));
    }
    if (owned) {
      const auto original = AsText(Read(saved, L"Exists")) == L"1" ? Read(saved, L"Original") : Value{};
      Write(change.path, change.name, original);
      Prune(change.path, AsText(Read(saved, L"Ancestor")));
    }
  }
  Check(RegDeleteTreeW(HKEY_CURRENT_USER, backup_.c_str()));
  const auto deleted = RegDeleteKeyW(HKEY_CURRENT_USER, backup_.c_str());
  if (deleted != ERROR_FILE_NOT_FOUND) Check(deleted);
  Notify();
}
}  // namespace folder_defaults
