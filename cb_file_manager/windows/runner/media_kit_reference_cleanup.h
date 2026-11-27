#ifndef RUNNER_MEDIA_KIT_REFERENCE_CLEANUP_H_
#define RUNNER_MEDIA_KIT_REFERENCE_CLEANUP_H_

#include <windows.h>

#include <string>

// media_kit 1.2.6 persists a raw native pointer under a PID-only filename in
// debug builds to support Dart hot restart. An OS process with a reused PID
// cannot restore that pointer. Clear only its own file before creating any
// Flutter engine, never during Dart hot restart or secondary engine startup.
inline DWORD ClearStaleMediaKitReferenceFile(const std::wstring& directory,
                                            DWORD process_id) {
  if (directory.empty()) return ERROR_PATH_NOT_FOUND;
  std::wstring path = directory;
  if (path.back() != L'\\' && path.back() != L'/') path += L'\\';
  path += L"com.alexmercerind.media_kit.NativeReferenceHolder.";
  path += std::to_wstring(process_id);
  if (DeleteFileW(path.c_str())) return ERROR_SUCCESS;
  const DWORD error = GetLastError();
  return error == ERROR_FILE_NOT_FOUND ? ERROR_SUCCESS : error;
}

inline DWORD ClearCurrentProcessMediaKitReferenceFile() {
  std::wstring directory(MAX_PATH + 1, L'\0');
  for (;;) {
    const DWORD length = GetTempPathW(static_cast<DWORD>(directory.size()),
                                     directory.data());
    if (length == 0) return GetLastError();
    if (length < directory.size()) {
      directory.resize(length);
      return ClearStaleMediaKitReferenceFile(directory, GetCurrentProcessId());
    }
    directory.resize(static_cast<size_t>(length) + 1);
  }
}

#endif  // RUNNER_MEDIA_KIT_REFERENCE_CLEANUP_H_
