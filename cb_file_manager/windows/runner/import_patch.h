#ifndef RUNNER_IMPORT_PATCH_H_
#define RUNNER_IMPORT_PATCH_H_

#include <windows.h>

// Replaces |function| imported from |dll| in |module|'s import table with
// |replacement|, storing the previous target in |original| before the swap.
// Returns false when |module| does not import that function by name.
bool PatchImport(HMODULE module, const char *dll, const char *function,
                 void *replacement, void **original);

#endif  // RUNNER_IMPORT_PATCH_H_
