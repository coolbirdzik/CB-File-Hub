#include "../folder_defaults.h"
#include <iostream>

// Test-owned command-line driver for the same registration code used by the
// Flutter channel. Not linked or installed into the application.
int wmain(int argc, wchar_t** argv) {
  try {
    folder_defaults::Registration registration;
    if (argc == 2 && std::wstring(argv[1]) == L"restore") {
      registration.Restore();
      std::cout << "restored\n";
      return 0;
    }
    if (argc != 3) return 2;
    const std::wstring action = argv[1];
    const std::wstring executable = argv[2];
    if (action == L"enable") registration.Enable(executable);
    else if (action != L"status") return 2;
    const auto status = registration.Query(executable);
    std::cout << "{\"enabled\":" << (status.enabled ? "true" : "false")
              << ",\"canRestore\":" << (status.can_restore ? "true" : "false")
              << ",\"partial\":" << (status.partial ? "true" : "false") << "}\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
