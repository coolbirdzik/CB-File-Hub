# Native file drag crash investigation

## Confirmed evidence

- Windows Application Error event at 2026-09-05 16:21:08 Asia/Saigon:
  `cb_file_hub.exe` 1.1.4.2, `combase.dll` 10.0.26100.9278,
  exception `0xc0000005`, offset `0x10ad05`.
- Local dump: `%LOCALAPPDATA%/CrashDumps/cb_file_hub.exe.42764.dmp`.
  The process had run for approximately 51 minutes.
- Microsoft symbols and the matching app PDB resolve the fault to:

  ```text
  combase!CComApartment::ClassicSTAQueueMessage+0x29
  combase!CComApartment::ClassicSTAPostMessage
  combase!OXIDEntry::PostCall
  ... CStdMarshal::RemoteAddRef / UnmarshalObjRef ...
  combase!InternalGetWindowPropInterface2
  ole32!UnmarshalFromEndpointProperty
  ole32!CDragOperation::GetDropTarget / UpdateTarget
  ole32!DoDragDrop
  cb_file_hub!WindowUtilsPlugin::HandleMethodCall+0x16c4
  ```

  App-frame locals identify the file-drag branch (`encoded_paths`, `paths_it`),
  not the tab-drag branch. The fault dereferences a null pointer at `0x180`
  while resolving the drop target. The dump does not establish which component
  invalidated the target apartment. It is not sufficient to blame AXTree.

## Fix made during investigation

`file_operations_plugin.cpp` had definite COM lifetime defects:

- Successful copy/move uninitialized COM before its `ComPtr<IFileOperation>`
  and destination `IShellItem` were released.
- Early returns leaked COM initialization; `S_FALSE` was not balanced.
- Recycle Bin enumeration also uninitialized before releasing Shell interfaces.
- Initialization failures did not stop subsequent COM calls.

A scoped apartment now outlives the interfaces, balances every successful
initialization, and covers early returns. This follows the
[Microsoft COM lifetime contract](https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-couninitialize).
It fixes those defects; causality for the recorded drag crash remains unproven.

## Validation

- Native test compiled against the pre-change implementation fails with
  `Worker leaked its COM apartment` after an invalid destination.
- Patched implementation passes invalid-destination cleanup, nested COM
  initialization (`S_FALSE`), and three real copy/move cycles, checking the
  source/destination files and their contents.
- Run again from Visual Studio Developer PowerShell with
  `powershell -File scripts/test_windows_com.ps1` after a Debug Windows build.
- Existing Material and Fluent tooltip semantics widget tests: 2 passed on
  Flutter 3.47.2. They do not exercise the Windows AXTree bridge.

## Remaining verification

The supplied AXTree message matches an
[upstream Flutter issue](https://github.com/flutter/flutter/issues/182444).
The shared tooltip wrappers already address known anchor/identity problems;
passing their widget tests does not establish that all app screens are covered.

Two running Debug app processes were left running. They still use the old
executable. A fresh Windows app build and a long-session native file-drag repro
are needed to determine whether the recorded crash recurs. No claim is made
that the COM fix eliminates the AXTree log or every drag crash.
