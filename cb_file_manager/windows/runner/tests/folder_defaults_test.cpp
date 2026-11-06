#include "../folder_defaults.h"
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {
void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
void Put(const std::wstring& path, const wchar_t* name, const void* data,
         DWORD size, DWORD type = REG_SZ) {
  HKEY key = nullptr;
  Require(RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0,
                          KEY_ALL_ACCESS, nullptr, &key, nullptr) == ERROR_SUCCESS, "create key");
  const auto result = RegSetValueExW(key, name, 0, type, static_cast<const BYTE*>(data), size);
  RegCloseKey(key);
  Require(result == ERROR_SUCCESS, "write value");
}
void Text(const std::wstring& path, const wchar_t* name, const std::wstring& value,
          DWORD type = REG_SZ) {
  Put(path, name, value.c_str(), static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)), type);
}
std::vector<BYTE> Get(const std::wstring& path, const wchar_t* name, DWORD* type) {
  HKEY key = nullptr;
  Require(RegOpenKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, KEY_READ, &key) == ERROR_SUCCESS, "read key");
  DWORD size = 0;
  Require(RegQueryValueExW(key, name, nullptr, type, nullptr, &size) == ERROR_SUCCESS, "read size");
  std::vector<BYTE> bytes(size);
  const auto result = RegQueryValueExW(key, name, nullptr, type, bytes.data(), &size);
  RegCloseKey(key);
  Require(result == ERROR_SUCCESS, "read bytes");
  return bytes;
}
bool KeyExists(const std::wstring& path) {
  HKEY key = nullptr;
  const auto result = RegOpenKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, KEY_READ, &key);
  if (key) RegCloseKey(key);
  return result == ERROR_SUCCESS;
}
}

int main() {
  const auto root = L"Software\\CBFileHubTests\\FolderDefaults-" + std::to_wstring(GetCurrentProcessId());
  const auto classes = root + L"\\Classes";
  const auto backup = root + L"\\Backup";
  const auto shell = classes + L"\\Directory\\shell";
  const auto command = shell + L"\\open\\command";
  try {
    const auto executable = folder_defaults::ExecutablePath();
    folder_defaults::Registration registration(classes, backup);
    Require(!registration.Query(executable).enabled, "initial state");
    Text(shell, L"", L"previous-verb", REG_EXPAND_SZ);
    const BYTE original[] = {1, 0, 255, 17, 0};
    Put(command, L"", original, sizeof(original), REG_BINARY);
    Text(command, L"Unrelated", L"retain me");
    Text(command, L"DelegateExecute", L"");
    const auto empty = classes + L"\\Drive\\shell\\open";
    HKEY key = nullptr;
    Require(RegCreateKeyExW(HKEY_CURRENT_USER, empty.c_str(), 0, nullptr, 0,
                            KEY_ALL_ACCESS, nullptr, &key, nullptr) == ERROR_SUCCESS, "pre-existing empty key");
    RegCloseKey(key);
    registration.Enable(executable);
    Require(registration.Query(executable).enabled, "enabled state");
    Require(registration.Query(executable).can_restore, "backup state");
    registration.Enable(executable);  // Must not overwrite the original backup.
    registration.Restore(L"another-installation.exe");
    Require(registration.Query(executable).enabled, "another installation cannot uninstall our default");
    registration.Restore();
    DWORD type = 0;
    Require(Get(command, L"", &type) == std::vector<BYTE>(original, original + sizeof(original)) &&
                type == REG_BINARY, "exact binary restoration");
    const auto previous = Get(shell, L"", &type);
    Require(type == REG_EXPAND_SZ && std::wstring(reinterpret_cast<const wchar_t*>(previous.data())) ==
                L"previous-verb", "original value type restoration");
    Require(KeyExists(empty), "pre-existing empty key retained");
    Require(!KeyExists(empty + L"\\command"), "new empty keys pruned");
    Get(command, L"Unrelated", &type);
    Require(Get(command, L"DelegateExecute", &type).size() == sizeof(wchar_t), "existing empty value retained");
    Require(!registration.Query(executable).can_restore, "journal removed");
    registration.Restore();  // Idempotent.
    // Fail each write boundary, including after changing a parent shell verb
    // but before its command. The journal must roll the entire change back.
    for (size_t fail_at = 0; fail_at < 8; ++fail_at) {
      folder_defaults::Registration failing(classes, backup, [fail_at](size_t index) {
        if (index == fail_at) throw std::runtime_error("injected registry write failure");
      });
      bool failed = false;
      try { failing.Enable(executable); } catch (const std::exception&) { failed = true; }
      Require(failed, "failure injection reached");
      const auto restored = Get(shell, L"", &type);
      Require(type == REG_EXPAND_SZ &&
                  std::wstring(reinterpret_cast<const wchar_t*>(restored.data())) == L"previous-verb",
              "failed enable restores parent shell default");
      Require(Get(command, L"", &type) == std::vector<BYTE>(original, original + sizeof(original)) &&
                  type == REG_BINARY, "failed enable restores original command");
      Require(!failing.Query(executable).can_restore, "failed enable rollback clears journal");
    }
    registration.Enable(executable);
    Text(command, L"", L"third-party.exe \"%1\"");
    Text(command, L"DelegateExecute", L"new-handler");
    Require(!registration.Query(executable).enabled && registration.Query(executable).partial,
            "partial registration detected");
    bool refused = false;
    try { registration.Enable(executable); } catch (const std::exception&) { refused = true; }
    Require(refused, "partial registration cannot replace the backup");
    registration.Restore();
    const auto external = Get(command, L"", &type);
    Require(std::wstring(reinterpret_cast<const wchar_t*>(external.data())) == L"third-party.exe \"%1\"",
            "later application choice preserved");
    const auto delegate = Get(command, L"DelegateExecute", &type);
    Require(std::wstring(reinterpret_cast<const wchar_t*>(delegate.data())) == L"new-handler",
            "later delegate preserved");
    RegDeleteTreeW(HKEY_CURRENT_USER, root.c_str());
    std::cout << "FOLDER_DEFAULTS_NATIVE_OK: enable, exact restore, repeat, partial, external takeover, empty keys\n";
    return 0;
  } catch (const std::exception& error) {
    RegDeleteTreeW(HKEY_CURRENT_USER, root.c_str());
    std::cerr << error.what() << '\n';
    return 1;
  }
}
