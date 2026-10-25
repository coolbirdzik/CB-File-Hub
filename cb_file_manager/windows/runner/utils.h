#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <flutter/dart_project.h>

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Every engine in the process runs its UI isolate on its own thread, so one
// busy window cannot stall the others or the native tab drag. Flutter plans to
// drop that option; CB_MERGED_UI_THREAD=1 runs the merged (future default)
// policy so the app can be checked against it before then.
flutter::UIThreadPolicy PreferredUIThreadPolicy();

// Allows renderer A/B profiling without changing the deployed default.
// Dedicated lightweight windows still enforce their existing Skia policy.
flutter::ImpellerSwitch PreferredImpellerSwitch();

#endif  // RUNNER_UTILS_H_
