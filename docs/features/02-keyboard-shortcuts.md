# Keyboard Shortcuts

Desktop shortcuts use Command (`⌘`) on macOS and Control (`Ctrl`) on Windows/Linux. Existing Ctrl aliases remain available on macOS. Extra modifiers are matched exactly; holding a destructive shortcut does not repeatedly invoke it.

## Tabs and windows

These bindings apply throughout the tab shell, including while editing a search or path field. A modal dialog owns its focus, so tab commands do not act on the tab behind it.

| Action | macOS | Windows / Linux |
|--------|-------|-----------------|
| New tab | `⌘T` | `Ctrl+T` / `Ctrl+N` |
| Close active tab | `⌘W` | `Ctrl+W` |
| New window | `⌘N` | `Ctrl+Shift+N` |
| Switch to tab 1–9 | `⌘1`–`⌘9` | `Ctrl+1`–`Ctrl+9` |
| Next / previous tab | `Ctrl+Tab` / `Ctrl+Shift+Tab`; `⌘Shift+]` / `⌘Shift+[` | `Ctrl+Tab` / `Ctrl+Shift+Tab` |
| Toggle split view | `⌘\` | `Ctrl+\` |

Closing a tab uses the same behavior as its close button: the adjacent tab becomes active. Closing the last tab leaves the empty tab view.

For compatibility, macOS also retains `Ctrl+N` for a new tab and `Ctrl+Shift+N` for a new window. `⌘Shift+N` creates a folder in the folder browser instead.

## Files and selection

File commands act on the focused or selected items in the active view, where that view supports the action. They leave text editing, clipboard shortcuts, and deletion inside text fields to the text field itself. Search remains available while editing.

| Action | macOS | Windows / Linux |
|--------|-------|-----------------|
| Copy / cut / paste | `⌘C` / `⌘X` / `⌘V` | `Ctrl+C` / `Ctrl+X` / `Ctrl+V` |
| Select all | `⌘A` | `Ctrl+A` |
| Toggle individual selection | `⌘Click` | `Ctrl+Click` |
| Extend selection | `Shift+Click` / `Shift+Arrow` | `Shift+Click` / `Shift+Arrow` |
| Rename | `Return` / `F2` | `F2` |
| Move to Trash | `⌘Backspace` / `Delete` | `Delete` |
| Request permanent deletion | `⌘Option+Backspace` / `Shift+Delete` | `Shift+Delete` |
| Search / refocus search | `⌘F` | `Ctrl+F` |
| Refresh | `⌘R` / `F5` | `Ctrl+R` / `F5` |

The Delete key on a typical Mac keyboard produces Backspace; use `⌘Backspace` to move files to Trash. Deletion still follows the view's existing confirmation flow. Views such as tags and Trash keep their own deletion semantics.

## Folder navigation

| Action | macOS | Windows / Linux |
|--------|-------|-----------------|
| Move focus | Arrow keys | Arrow keys |
| Open focused item | `⌘O` / `⌘↓` | `Enter` |
| Previous / next history entry | `⌘[` / `⌘]`; `Option+←` / `Option+→` | `Alt+←` / `Alt+→` |
| Back in history | `Backspace` | `Backspace` |
| Parent folder | `⌘↑` / `Option+↑` | `Alt+↑` |
| New folder | `⌘Shift+N` | Use the existing create-folder control |

History shortcuts are also available on file surfaces with history callbacks. Parent-folder commands apply in the folder browser; new-folder creation is available in local filesystem directories, including mounted volumes. Plain typing performs type-ahead selection; its buffer resets after one second. Command chords do not enter the type-ahead buffer.

## Dialogs

`Enter` confirms the focused action, `Escape` cancels, and `Tab` moves focus between controls. Image and video viewers retain their own media controls. macOS continues to handle standard application commands such as `⌘Q`, `⌘H`, and `⌘M` through its native menu.
