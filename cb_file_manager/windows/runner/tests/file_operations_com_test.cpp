// Native regression test: compile with the Flutter Windows wrapper/import libs.
// Includes the implementation to exercise its worker functions without a Dart
// engine or a platform-channel mock.
#ifndef CB_FILE_OPERATIONS_IMPLEMENTATION
#define CB_FILE_OPERATIONS_IMPLEMENTATION "../file_operations_plugin.cpp"
#endif
#include CB_FILE_OPERATIONS_IMPLEMENTATION

#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace fs = std::filesystem;

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

void CheckApartmentReleased() {
  // A leaked MTA initialization causes RPC_E_CHANGED_MODE here. This also
  // catches unbalanced S_FALSE calls when the worker already had an apartment.
  const HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (SUCCEEDED(hr)) CoUninitialize();
  Check(hr == S_OK, "Worker leaked its COM apartment");
}

int main() {
  const fs::path sandbox = fs::temp_directory_path() /
      (L"cb_com_regression_" + std::to_wstring(GetCurrentProcessId()) + L"_" +
       std::to_wstring(GetTickCount64()));
  try {
    Check(fs::create_directory(sandbox), "Could not create isolated sandbox");
    const fs::path source = sandbox / L"source.txt";
    const fs::path copied = sandbox / L"copied";
    const fs::path moved = sandbox / L"moved";
    fs::create_directory(copied);
    fs::create_directory(moved);
    std::ofstream(source) << "COM lifetime regression";

    using file_operations_plugin::PerformFileOperation;

    // Failed destination lookup returns after IFileOperation was created.
    Check(!PerformFileOperation(nullptr, {source.wstring()},
                                (sandbox / L"missing" / L"destination").wstring(),
                                false),
          "An invalid destination unexpectedly succeeded");
    CheckApartmentReleased();

    // Model an already-initialized worker: S_FALSE must be balanced too.
    Check(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK,
          "Could not initialize the worker MTA");
    Check(!PerformFileOperation(nullptr, {source.wstring()},
                                (sandbox / L"missing" / L"destination").wstring(),
                                false),
          "An invalid destination unexpectedly succeeded");
    CoUninitialize();
    CheckApartmentReleased();

    for (int i = 0; i < 3; ++i) {
      Check(PerformFileOperation(nullptr, {source.wstring()}, copied.wstring(),
                                 false), "Native copy failed");
      Check(fs::exists(source) && fs::exists(copied / source.filename()),
            "Copy did not preserve source and create destination");
      CheckApartmentReleased();
      Check(PerformFileOperation(nullptr,
                                 {(copied / source.filename()).wstring()},
                                 moved.wstring(), true), "Native move failed");
      Check(!fs::exists(copied / source.filename()), "Move left the source file");
      std::ifstream content(moved / source.filename());
      std::string actual;
      std::getline(content, actual);
      Check(actual == "COM lifetime regression", "Moved file content changed");
      content.close();
      CheckApartmentReleased();
      fs::remove(moved / source.filename());
    }

    // Cleanup names are limited to the fresh sandbox and its known children.
    fs::remove(source);
    fs::remove(copied);
    fs::remove(moved);
    fs::remove(sandbox);
    std::cout << "PASS: failure, S_FALSE, and 3 native copy/move cycles\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << "\nSandbox retained: "
              << sandbox << '\n';
    return 1;
  }
}
