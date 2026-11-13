## File Browser Grid + Preview Mode

### Home Browse: storage locations and WSL

Browse shows Windows drive letters and registered WSL distributions. Storage
avatars identify the Windows system volume, ordinary disks, removable media,
network drives and Linux. Group filters above the collection expose each group
and its count, including Linux · WSL even when its cards start below the fold.
Grid, tiles and list show groups; keyboard navigation follows their displayed
order. Details, tree and columns retain their own layouts. Hierarchical roots
reuse the same display names and storage icons as the cards.

The drawer's Drives section loads that same inventory, including WSL. Its
directory adapter retains drive names, kinds and protected-volume flags for both
Fluent and Material renderers; both use the shared storage avatar. Selecting a
WSL entry opens its UNC root in the current tab. Rendering the drawer never
probes a known volume/WSL root with `typeSync`, so it does not start Linux merely
to label or highlight a row. Coverage: `test/ui/drawer_storage_test.dart`.

`DriveInventoryService` adds `WindowsWslInventory` results to the physical drive
inventory. It runs `wsl.exe --list --quiet` with a four-second timeout, decodes
redirected UTF-16 output, and maps each distro to `\\wsl.localhost\<name>\`.
Missing WSL or command failure leaves the Windows drives available. Enumeration
does not list distro directories; opening a location uses the normal UNC file
browser. WSL capacity is left unknown during discovery and is excluded from the
physical-capacity sum. Format, Windows volume cleanup and BitLocker are not
offered for a WSL share. Its terminal action opens the selected distribution.

Microsoft references: [list distributions](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
and [WSL UNC file access](https://learn.microsoft.com/en-us/windows/dev-environment/wsl-interop).
Coverage: `test/services/drive/windows_wsl_inventory_test.dart`,
`test/ui/screens/home/drive_browser_content_test.dart`, and
`test/ui/screens/home/drive_hierarchy_test.dart`.

### Requirements
- Desktop only: add a new view mode alongside list/grid/details.
- Preview pane on the right in grid mode; allow toggle show/hide.
- Resize the preview pane by dragging the divider.
- Preview images, videos, and PDFs; reuse existing video player and image viewer for open actions.
- Not available on mobile.

### Behavior
- Uses `ViewMode.gridPreview` for the grid + preview layout.
- Preview pane width is resizable and persisted; default width is 360px.
- Preview pane width is constrained:
  - Minimum 280px.
  - Maximum is `min(80% of window width, window width - 360px)`.
  - If the window is too narrow, the layout falls back to grid-only.
- Toggle button in the app bar hides/shows the preview pane.
- Single click selects items in grid preview; double click opens.

### Preview Support
- Video: uses the existing `VideoPlayer.file` widget.
- Image: inline `InteractiveViewer` preview; open action uses the existing image viewer.
- PDF: rendered via `pdfx` (`PdfView`).
- Network paths show a placeholder (no preview) to avoid streaming file reads.

### Custom desktop pane layout

- The tabbed file browser supports arranging Files, Preview, and Properties & Tags.
- The initial arrangement remains Files on the left, Preview on the right, and
  Properties & Tags below. Existing visibility, preview width, and properties
  height preferences still provide the initial defaults.
- Drag the grip in a pane header over another pane. Its nearest edge chooses
  left, right, above, or below; the shaded half shows the destination before release.
- While dragging, a thin strip appears along each outer edge of the whole layout.
  Dropping on it docks the pane across the full width (top/bottom) or full height
  (left/right), e.g. Properties & Tags as a full-width bar under Files and Preview.
- Drag any divider to resize the adjoining panes immediately with the pointer.
  No size overlay appears during the drag. Updates remain local to the active split,
  reuse its mounted contents, and repaint panes separately. The final proportions
  are shared and saved on release; cancelling restores the previous sizes.
- Each divider stores the pixel size of the pane side away from the file list, so
  Preview and Properties & Tags keep their own widths (or heights) independently:
  a divider only moves its two neighbours, and a narrower window shrinks the file
  list. Layouts saved with the older proportion format still load.
- Grid, Masonry, and Tiles keep the existing item delegate while the column
  count and thumbnail size are unchanged. Cell measurement reuses the thumbnail
  subtree as gutters resize, instead of rebuilding every video tile per pixel.
  Data, selection, zoom, and inherited theme changes still refresh the contents.
- Grid and Masonry also reuse their item delegate across column-count changes;
  keyboard geometry updates do not rebuild the whole folder tab. Folder thumbnail
  rendering performs no synchronous file checks, and loading covers use a static
  placeholder instead of running one shimmer animation per folder.
- Grid hit areas read the attached tile's current bounds during selection,
  avoiding per-tile build callbacks and post-frame measurements during resize.
- Pane positions and divider proportions are saved in `file_pane_layout` using
  the existing user preferences storage, shared across folder tabs and restored
  after restarting the app. Hiding a pane preserves its saved place and size.
- The restore button in the Files header restores the original arrangement.
- Pane drags only begin on the header grip, preserving file drag/drop and
  preview controls. Moving panes preserves their mounted contents and tag drafts.
- Small windows temporarily hide auxiliary panes without overwriting the saved
  layout. Mobile keeps its existing file browser.

### Storage
- Preferences are stored in `UserPreferences`:
  - `preview_pane_visible`
  - `preview_pane_width`

### Platform Notes
- Mobile maps `gridPreview` to `grid` when loading view mode preferences.

### Files
1. `cb_file_manager/lib/ui/widgets/file_preview_pane.dart`
2. `cb_file_manager/lib/ui/widgets/file_list_view_builder.dart`
3. `cb_file_manager/lib/ui/screens/folder_list/folder_list_state.dart`
4. `cb_file_manager/lib/ui/mixins/preferences_manager_mixin.dart`
5. `cb_file_manager/lib/helpers/core/user_preferences.dart`
6. `cb_file_manager/lib/ui/widgets/file_pane_layout.dart`
7. `cb_file_manager/lib/ui/widgets/file_pane_layout_model.dart`
