# Windows default folder application

The EXE/MSI desktop build exposes a default-folder-opener action
in Settings. Windows has no ordinary Default Apps category for a file manager;
this feature uses per-user Shell command overrides. MSIX/Store packages cannot
enable it. See the [desktop implementation](14-desktop-default-file-manager.md)
for shared folder launch handling, macOS and Linux.

## Native registration

`windows/runner/folder_defaults.cpp` is the native core. The existing
`cb_file_manager/app_icon` channel exposes `folderDefaultStatus`, `setFolderDefault`
and `restoreFolderDefault` to `DefaultFileManagerService`.

Only these HKCU values under `Software\Classes` are changed:

- `Directory\shell` and `Drive\shell`: default verb `open`.
- Their `shell\open\command`: default command and empty `DelegateExecute`.
- `CLSID\{52205fd8-5dfb-447d-801a-d0b52f2e83e1}\shell\opennewwindow\command`:
  default command and empty `DelegateExecute`, for the Explorer Win+E entry.

Filesystem commands use `--open-folder "%1\."`. The suffix prevents a drive-root
trailing backslash from escaping the closing quote in Windows argv parsing.
The Win+E command uses `--open-folder` with no path, opening Home. Generic virtual
`Folder` verbs, protected `UserChoice` associations, HKLM, system file pickers and
Explorer-internal navigation are not changed.

## Restore and ownership

Before changing associations, the core journals every original value's presence,
type and bytes in `HKCU\Software\COOLBIRDZIK\CB File Hub\FolderDefaultBackup`, plus
the installed values and original key ancestry. The complete journal is flushed
before writing Shell values. A named per-session mutex serializes app windows.

Enable failures invoke rollback. Repeated enable never replaces the original
backup. An incomplete/external replacement is reported as partial; restore must
be performed before enabling again. Restore only writes values still owned by
the recorded registration, leaves other applications' later choices intact and
removes newly created empty keys without removing pre-existing empty keys.
The journal supports retry after an interrupted restore.
The native test injects failure at each of the eight write boundaries, including
between a shell default and its command, and verifies the original state returns.

`--restore-folder-default` is a native, headless app command used before Inno/WiX
uninstall removes files. It restores only a backup belonging to that exact
executable path. MSI major upgrades retain registration. Since defaults are
per-user, uninstall cleanup applies to the invoking user, not other OS accounts;
those users can restore from Settings before removing their app copy.

## Evidence and limits

The isolated native tests cover enable, repeat, exact value/type restoration,
empty/absent values, key cleanup, partial registration and external takeover.
Dart tests cover folder parsing, real peer sockets and Settings state/failure UI.
Windows release builds must pass after native edits.

On 2026-11-06 the final Windows release build passed. Live Shell `open` launched
the app on a Unicode/spaced/percent folder; opening `C:\` and the Explorer
`opennewwindow` CLSID entry handed off to that same running normal window, adding
the drive and Home tabs. The temporary sender processes exited. An encoded
file-URI argument also opened the intended folder with spaces, `&` and `#`.
This host's Shell did not resolve the file URI directly; URI decoding was checked
by passing it to the app executable.

The shipped `--restore-folder-default` command succeeded, and all five touched
Registry key/value snapshots matched their pre-test state exactly. Final native
status was disabled with no restoration journal. Evidence is in the local,
git-ignored `build/folder-default-tests/` directory. These checks do not establish
compatibility with every Windows version or third-party Shell extension.
Actual keyboard input and visual inspection require a working UI automation
channel or manual user testing. The development host currently reports its
Computer Use native pipe unavailable.

Sources: [Microsoft Shell verbs](https://learn.microsoft.com/en-us/windows/win32/shell/launch),
[Microsoft default-app platform](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/default-apps-platform),
[Files default file manager](https://www.files.community/docs/customize-settings/advanced).
