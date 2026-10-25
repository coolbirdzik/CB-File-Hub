# CB File Hub patches to xterm.dart

Source: the published `xterm` 4.0.0 package from pub.dev, upstream
https://github.com/TerminalStudio/xterm.dart. Its MIT license is in `LICENSE`.
Only runtime sources and package metadata are vendored. Runtime sources are
formatted with the workspace's Dart SDK.

The unused `equatable` runtime dependency was removed: none of the vendored
sources import it. This allows the app to adopt Equatable 3 without adding an
unnecessary compatibility constraint to the terminal.

## 4.0.0+cb.1 — Flutter 3.47.2 Windows text input

`lib/src/ui/custom_text_edit.dart` now passes `View.of(context).viewId` to
`TextInputConfiguration` when attaching the terminal's input client. Without
it, the Windows engine rejects `TextInput.setClient` with “view ID is null”;
subsequent editing updates fail because no native client was attached.

Use the containing view, rather than assuming the implicit/first view, so
terminal input remains scoped to the right window. The input path still uses
Flutter's text input/IME support. No global channel interception or hardware-
keyboard-only fallback is installed.

The local Flutter constraint matches the workspace SDK. Revisit this patch when
updating xterm; remove the vendor dependency when an upstream release includes
equivalent view-aware input. Never patch a user's global Pub cache.

Regression tests (from `cb_file_manager/`):

```powershell
flutter test test/ui/screens/network_browsing/ssh_terminal_input_test.dart
```

They cover native client configuration, text/IME output, control and navigation
keys, connect/disconnect, refocus and disposal.
