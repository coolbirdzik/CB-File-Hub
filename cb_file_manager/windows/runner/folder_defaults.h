#ifndef CB_FOLDER_DEFAULTS_H_
#define CB_FOLDER_DEFAULTS_H_

#include <windows.h>
#include <string>
#include <functional>

namespace folder_defaults {
struct Status {
  bool available = true;
  bool enabled = false;
  bool can_restore = false;
  bool partial = false;
};

// Optional roots let native tests exercise the real registry code without
// touching any Shell association. Production always uses the defaults.
class Registration {
 public:
  explicit Registration(
      std::wstring classes = L"Software\\Classes",
      std::wstring backup = L"Software\\COOLBIRDZIK\\CB File Hub\\FolderDefaultBackup",
      std::function<void(size_t)> before_change = {});
  Status Query(const std::wstring& executable) const;
  void Enable(const std::wstring& executable);
  void Restore(const std::wstring& expected_executable = L"");
 private:
  std::wstring classes_;
  std::wstring backup_;
  std::function<void(size_t)> before_change_;
};
std::wstring ExecutablePath();
}  // namespace folder_defaults
#endif
