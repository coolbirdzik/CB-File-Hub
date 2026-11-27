// Standalone Windows unit test; no Flutter engine or real player is started.
#include "../media_kit_reference_cleanup.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace {
void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
}  // namespace

int main() {
  namespace fs = std::filesystem;
  const auto directory = fs::temp_directory_path() /
                         (L"cb-media-kit-cleanup-test-" +
                          std::to_wstring(GetCurrentProcessId()));
  const std::wstring prefix = L"com.alexmercerind.media_kit.NativeReferenceHolder.";
  const DWORD process_id = GetCurrentProcessId();
  const auto stale = directory / (prefix + std::to_wstring(process_id));
  const auto other = directory / (prefix + L"other-process");
  try {
    Check(fs::create_directory(directory), "Could not create test directory");
    std::ofstream(stale) << "old reference";
    std::ofstream(other) << "unrelated reference";
    Check(ClearStaleMediaKitReferenceFile(directory.wstring(), process_id) ==
              ERROR_SUCCESS, "Stale reference cleanup failed");
    Check(!fs::exists(stale), "Current process file was not removed");
    Check(fs::exists(other), "An unrelated file was removed");
    Check(ClearStaleMediaKitReferenceFile(directory.wstring(), process_id) ==
              ERROR_SUCCESS, "Missing reference should be harmless");

    std::ofstream(stale) << "locked reference";
    HANDLE lock = CreateFileW(stale.c_str(), GENERIC_READ, 0, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(lock != INVALID_HANDLE_VALUE, "Could not lock test reference");
    const DWORD error = ClearStaleMediaKitReferenceFile(directory.wstring(), process_id);
    CloseHandle(lock);
    Check(error != ERROR_SUCCESS, "Locked reference must stop unsafe startup");
    Check(fs::exists(stale), "Locked reference was unexpectedly removed");
    Check(ClearStaleMediaKitReferenceFile(directory.wstring(), process_id) ==
              ERROR_SUCCESS, "Cleanup did not recover after unlock");

    // Exercise the actual entry point with the test's own PID and temp path.
    // The environment override belongs only to this standalone test process.
    std::ofstream(stale) << "previous process reference";
    Check(SetEnvironmentVariableW(L"TMP", directory.c_str()) != 0 &&
              SetEnvironmentVariableW(L"TEMP", directory.c_str()) != 0,
          "Could not set test temporary directory");
    Check(ClearCurrentProcessMediaKitReferenceFile() == ERROR_SUCCESS,
          "Cold-start cleanup failed");
    Check(!fs::exists(stale), "Cold-start cleanup did not remove the stale file");
    Check(fs::exists(other), "Cold-start cleanup touched an unrelated file");
    fs::remove(other);
    fs::remove(directory);
    std::cout << "media_kit_reference_cleanup_test passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
