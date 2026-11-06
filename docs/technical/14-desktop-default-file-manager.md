# Desktop default folder application

Implemented on 2026-11-06. Settings > Default file manager offers **Set as default
for folders**, **Restore previous default**, and **Refresh status** on desktop.
Status is read from the operating system, not a saved enabled flag. Registration
happens only after the user chooses the action; installation never takes defaults.

On the primary desktop window, onboarding offers the same setup after theme and
language selection. Users can choose Not now, or explicitly set the default and
continue. Both exits persist `default_file_manager_onboarding_completed_v1`, so
the choice is offered once, including to existing users whose theme onboarding
was already complete. Already-default apps are acknowledged without a prompt;
unsupported/unavailable platforms, secondary windows and E2E mode skip the step.
Setup errors remain visible, and navigation is disabled while the OS change is
pending. Settings and onboarding use the same setup widget and service.

| Platform | Implementation | Coverage |
| --- | --- | --- |
| Windows EXE/MSI | Per-user Directory/Drive open verbs and Explorer's Win+E CLSID command | Native Registry journal and restoration. |
| macOS 12+ | AppKit default application for `UTType.folder` | Native open-URL queue, consent and restoration; requires Mac runtime validation. |
| Linux | XDG `inode/directory` default and user desktop entry | Local folder/URI arguments; requires GNOME/KDE runtime validation. |

These choices do not replace system file picker dialogs or APIs that explicitly
call a particular file manager. Windows MSIX/Store packages disable
Explorer redirection; the EXE/MSI editions expose it.

## Shared opening path

- `lib/services/desktop_integration/folder_launch_request.dart` validates absolute
  directory paths and local `file:` URIs, keeps raw percent signs intact, supports
  Unicode/spaces, deduplicates locations and creates tab payloads with folder names.
- `--open-folder` accepts one or more directories. With no path it opens Home,
  which is the Windows Win+E launch command. Invalid explicit locations produce
  visible feedback rather than silently opening Home.
- `main.dart` handles directory arguments before video startup. Valid folder
  requests can be sent to an existing normal window from the same executable
  through `DesktopWindowingService`. Otherwise a normal app launch creates tabs.
  Existing torrent, dedicated-video and environment window payloads keep their
  own startup routes. Mixed folder/video launches retain the main file shell.
- On Windows the sender grants foreground permission before peer delivery.
  Requests are acknowledged after validation and tab enqueueing; focus does not
  delay acknowledgement. Peer messages from a different executable are rejected.
- `FolderOpenBridge` attaches to the current `TabManagerBloc` and detaches when
  the shell is disposed. Native macOS folder events queue until the bridge is ready.

## Windows

See [Windows implementation](13-windows-default-file-manager.md) for exact keys,
backup ownership and uninstall behavior. No protected `UserChoice` data is edited.

## macOS

`macos/Runner/Info.plist` advertises `public.folder` with role Viewer and handler
rank Alternate. Packages and app bundles are not claimed as generic directories.
`AppDelegate.swift` queues incoming folder URLs and forwards other URLs to the
existing Flutter lifecycle delegates. `MainFlutterWindow.swift` registers the
folder channel and exposes default-handler methods on `cb_file_manager/macos_window`.

`FolderDefaults` uses `NSWorkspace.setDefaultApplication(at:toOpen:completion:)`,
available from macOS 12, matching this project's deployment target. macOS handles
any required consent. The previous application URL is saved in UserDefaults
before a change. Failure/cancellation is reported; success is verified by querying
the OS. Restore preserves a different application chosen later by the user.
Sources: [Apple API](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopen:completion:)),
[folder UTI](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/folder),
[document type keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html).

This changes ordinary folder associations, not all Finder behavior. Apple's
`activateFileViewerSelecting` explicitly activates Finder. Default-handler
registration also grants no additional filesystem permissions. Sources:
[Finder reveal API](https://developer.apple.com/documentation/appkit/nsworkspace/activatefileviewerselecting(_:)),
[open callbacks](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:openfiles:)).

## Linux

`package_linux_deb.sh` advertises `MimeType=inode/directory;` and `Exec=cb-file-hub %U`.
The Settings service installs a per-user `com.cb.cbfilehub.desktop` with an absolute,
correctly escaped executable path, `%U`, and `TryExec`; this also supports portable
installs at a stable path. The existing GTK runner forwards argv to Dart.

The service queries `xdg-mime query default inode/directory`, records the previous
desktop ID before requesting `xdg-mime default`, and verifies the selected ID.
A file lock protects the backup between app processes. Restore changes the default
only if CB File Hub is still selected, preserving another app selected later.
A pending backup must be restored before a new enable operation. Run these actions
in the logged-in desktop session, without sudo. Sources:
[XDG MIME associations](https://specifications.freedesktop.org/mime-apps/latest-single/),
[xdg-mime manual](https://manpages.debian.org/trixie/xdg-utils/xdg-mime.1.en.html),
[Exec field codes](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html).

A desktop-specific opener or shortcut can bypass MIME defaults. Supporting
`org.freedesktop.FileManager1.ShowItems` for every 'Show in folder' caller is a
separate D-Bus service feature and is not implemented here. FileChooser portals
also use a separate backend. Sources:
[FileManager1](https://wiki.freedesktop.org/www/Specifications/file-manager-interface/),
[FileChooser portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileChooser.html).

## Verification

Run from `cb_file_manager`:

```sh
flutter test test/services/desktop_integration test/ui/screens/settings/default_file_manager_settings_test.dart test/ui/screens/onboarding/default_file_manager_onboarding_test.dart test/services/windowing/torrent_window_focus_test.dart
flutter analyze
flutter build windows --release
```

Native Windows tests in `windows/runner/tests/folder_defaults_test.cpp` compile
with `folder_defaults.cpp`, `/std:c++17 /EHsc /W4 /WX`, and `advapi32.lib shell32.lib`.
They use a test-owned HKCU subtree, exercising exact raw-value restoration,
absent/empty values, existing empty keys, repeated enable/restore, external
application takeover and another installation's uninstall.
`folder_defaults_smoke.cpp` is a test-only driver for the same native code; it is
not shipped in the application.

Native macOS and Linux builds/runtime checks are pending on their respective
platforms. Their method-channel and Linux process/backup behavior have unit
coverage on Windows. UI automation on this Windows host currently has no native
pipe, so visual UI and actual keyboard Win+E behavior must not be claimed as
verified by those checks. Windows Shell dispatch and live app tabs can be checked
independently through the normal OS launcher and the app's window peer protocol.
