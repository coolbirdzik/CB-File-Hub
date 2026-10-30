# Tab Windows: Tear-off and Merge (Windows)

**Purpose**: Chrome-style tab windows. Drag a tab out of the tab strip to open
it in a new window that follows the cursor; drop a window's tab on another
window's tab strip to move it there.

## Architecture (Windows): one process, one engine per window

Windows uses the public Windows embedder API. `engine_window_host.cpp` owns
secondary `FlutterWindow`s, each with its own `FlutterViewController`, engine
and Dart isolate. There are no imports of Flutter's internal windowing APIs.
All tab, player, PiP, progress and torrent-options windows are created inside
the existing process. macOS and Linux retain their process launchers.

- `WindowsEngineHost` (`lib/services/windowing/windows_engine_host.dart`)
  reads an engine-specific startup context over `cb_file_manager/engine_windows`.
  Process environment variables are never changed to start a window. Each new
  window gets fresh startup options instead of inheriting another window's tabs,
  player arguments or PiP mode. Native plugins are registered per engine.
- Every engine owns its own widget tree, `TabManagerBloc`, navigator and GetIt
  locator. Widgets and `GlobalKey`s do not move across engines.
  `TabWindowTransfer` serializes tab identity, history, pinned/split state,
  pane toggles and mounted folder-view state (search, selection, sort/view/zoom,
  scroll position). The destination builds fresh widgets from the snapshot.
  Screens without a session capture hook rebuild from their tab path.
- Video Gallery transfers its library cards/counts and loaded file list, display
  options, search results/query, selection and scroll position. The destination
  uses that snapshot in its first frame instead of reloading metadata or scanning
  the collection. Searches still in progress resume in the destination. Large
  view snapshots are gzip-compressed in the tab payload to reduce native merge
  message size. Desktop resizing below 600dp keeps the desktop tab tree mounted
  rather than switching to the mobile tab view.
- The existing peer/registry sockets carry serialized tab payloads between
  engines. Native HWND-based preview and merge keep the drag responsive.
  A hidden pre-warmed spare engine supplies the next tear-off window.
- Each engine runs its UI isolate on its own thread
  (`UIThreadPolicy::RunOnSeparateThread`, `PreferredUIThreadPolicy()` in
  `windows/runner/utils.cpp`). Merged threads would put every window's Dart on
  the one platform thread: a busy window would stall the others, and the drag
  worker's `WM_COPYDATA` enter/drop/reveal sends (1 s timeouts) would wait on
  that Dart work, so a merge could fall back to a detach. Flutter logs that it
  will drop the separate-thread option; it is still present on master (October
  2026). Launch with `CB_MERGED_UI_THREAD=1` to run the merged policy and check
  tab drag, merge, tear-off, the context menu and video playback against it.
- All windows share the platform thread, so Windows no longer stops one of
  them taking the foreground from another. The window prepared during a tab
  drag is shown with `showWindowInactive` (window_manager's `show(inactive:)`
  still calls `SetForegroundWindow`). After a reveal, merge drop or
  `forceActivateWindow`, other windows yield for one second: a Flutter focus
  request in the window the tabs left would otherwise activate it and raise it
  over the new one. A click on another window ends the yield. A window's own
  drag loop marks it with a property; releasing a reveal hold no longer waits
  for another window's drag. The process-wide "a drag is running" flag is
  released when the mouse is, not after a dropped tear-off preview stops
  waiting for its window: otherwise the next tab drag fell back to the system
  move loop (Windows' snap bar at the top edge, no merging).
- `custom_frame_message.h` wraps the entire native message dispatch before
  Flutter/plugin delegates. Every tab switch sets the window title, and
  `DefWindowProc` can paint its native caption through the transparent tab
  strip despite the custom frame. `WM_SETTEXT`/`WM_SETICON` run with
  `WS_VISIBLE` cleared; `WM_NCACTIVATE` passes lParam -1 through the delegates
  to preserve focus notifications without requesting a caption repaint.
  `WM_NCPAINT` and uxtheme's `WM_NCUAHDRAWCAPTION`/`WM_NCUAHDRAWFRAME`
  (0xAE/0xAF) are suppressed. In particular, rebuilding the acrylic backdrop
  uses `RedrawWindow(RDW_FRAME)`, which otherwise redraws the native bar
  briefly during a merge. Each rebuild clears the material for a frame, so
  `WindowBackdrop::Sync` rebuilds only for new settings or after a size, state,
  show or theme change; activation and repeated requests only re-assert the
  Flutter view's accent. `scripts/test_windows_custom_frame.ps1` runs
  standalone Win32 coverage of repeated frame updates and focus/title/resize
  behavior without running app E2E tests.
  Maximizing a `WS_THICKFRAME` window makes the kernel add the resize frame
  (8 px) on every side after `WM_WINDOWPOSCHANGING`, keyed on the `WS_MAXIMIZE`
  bit, and the DWM glass then paints that overhang onto an adjacent monitor.
  `FitMaximizedPlacement` hides the bit for one placement so the window rect is
  the work area, restores it before `WM_SIZE` is derived (plugins still see a
  maximize) and puts the saved restore rect back when the window leaves the
  state. Placements already on the work area, such as every tab-title frame
  refresh, are left alone; window_manager's fullscreen (no `WS_THICKFRAME` and
  `WS_MAXIMIZEBOX`) is not fitted.
  Backdrop, fullscreen and reveal-hold state belong to each native window.
- Closing the primary window hides it while other user windows exist, retaining
  its coordinator/registry engine. Closing an idle secondary destroys its engine.
  Engines owning torrent downloads, tracked operations or model downloads stay
  hidden until their work finishes. The process exits with the last user window,
  except that hidden engines still running file operations or model downloads
  keep it alive until that work ends. Torrent ownership does not (seeding never
  finishes), and neither do spare or hidden torrent-options windows.
- aria2 ownership still uses an exclusive file lock. Takeover tokens contain an
  engine id as well as the PID, because every window now shares a PID. Services
  and caches are isolate-local; database/settings synchronization still applies.
- SQLite has one FFI worker registered with the public `IsolateNameServer` API.
  The primary engine initializes it before any spare engine starts. Other
  engines connect through sqflite's `isolatePortServer` API, without calling
  `sqfliteFfiInit` or creating SQLite handles in their own UI isolates.
  Closing a client engine leaves the worker and the shared connection alive.
  The worker still runs SQL off the UI thread; transaction IDs serialize work
  from different clients. Engines are separate isolate groups, so requests and
  rows cross a group boundary; `flutter test` cannot spawn such an isolate
  (`Isolate.spawnUri`), but the same exchange, blobs and transactions included,
  works on the Dart VM. External app processes retain the WAL/busy-timeout
  connection settings. `shared_desktop_database_test.dart` checks concurrent
  preference reads, transaction writes and client-isolate exit/reconnect.
- E2E mode does not initialize the engine host or create spare engines. Unit/widget
  coverage includes launch-channel contracts and serialized tab transfer. It does
  not prove real window dragging, DPI behavior or native-plugin runtime parity.

The former `CB_MULTI_PROCESS_WINDOWS` and `CB_WINDOWING_SELF_TEST` defines are
removed. Windows does not silently fall back to spawning another app process if
engine creation fails; it reports the failed window request.

## Gestures

| Gesture | Result |
|---------|--------|
| Drag a tab sideways | Reorder within the strip |
| Drag a tab (or a multi-selection) more than 28 px vertically **and** 10 px outside the strip | Tear-off: a new window appears with the dragged tab under the cursor and follows it |
| Release a dragged window over another window's tab strip | Merge: its tabs are inserted into the gap that opens under the cursor; the dragged window closes |
| Drag the only tab of a window | Moves the window (restoring it if maximized); releasing over another strip merges it. With no other tab window visible, the system move loop is used so Aero Snap still works |
| Drag the blank strip area | Plain window move (never merges) |

The detach band (strip ± 10 px) is wider than the attach area (the strip
itself). That gap keeps a freshly torn-off window from snapping straight back
into the strip it left.

- Every Flutter view installs `FlutterMouseInputGuard` before plugin setup.
  A held-button mouse move without capture is ignored, so a tab drag crossing
  windows cannot become a new press on a file underneath it (Flutter 3.47.2
  otherwise synthesizes that press). Losing capture cancels the source pointer
  through the engine's mouse-leave path; unmatched releases are discarded.
  Normal button releases still complete taps and right-click menus. Run the
  standalone Win32 unit test with `scripts/test_windows_mouse_input.ps1` in
  Visual Studio Developer PowerShell; it does not run app E2E tests.

## Tear-off path

The tabs stay in the source window until the drop, as in Chrome:

1. `_NativeTabDragHandle` records where in the tab the pointer was pressed.
   `_ModernTabBarState` builds a `TabDetachGeometry`: the tab's rect, the
   first-tab origin, the strip bottom, and the *window anchor* (the same grab
   point in a window whose strip is not scrolled).
2. `startTabTearOff`: the source captures the tab from the screen, plus its
   content below the strip when it is the active tab. It shows a layered
   **preview** window under the cursor in the same frame. A native thread with
   its own message loop moves the preview, so a busy UI thread anywhere cannot
   make it lag. It does the strip hover protocol itself and hides the preview
   over a strip.
3. Meanwhile `prepareTearOffWindow` loads the tabs into the pre-warmed
   **spare** (`prepare_tabs`). The spare is shown, but DWM-cloaked and off the
   taskbar, and marked `preparing` so no other tear-off takes it.
4. On release (`onTabTearOffEnded`):
   - **empty space**: the preview thread sends `CBFileHub.TabTearOffReveal.v1`
     to the readied spare, whose handle came back with `prepare_tabs`. The
     spare's window procedure places its content where the preview is and
     uncloaks before replying, and only then does the preview go. No Dart and
     no socket sit in between. Taskbar entry, role and focus follow in Dart
     (`_finishReveal`). Released before the spare was ready: `reveal_prepared`
     over the socket, with no waiting either. Without a free spare, a window
     is started normally.
   - **another window's strip**: the source sends the tabs there
     (`WM_COPYDATA`) and closes them; the spare is discarded back to `spare`.
   - **the source's own strip**: the tab returns and moves to the gap it
     opened. Escape cancels.
5. Spare replacement is left to the registry host when a spare becomes
   `normal` (1.5 s later). A spare with no normal window for two heartbeats
   exits.

When the preview cannot start, the older path is used: the spare is shown
cloaked with the tabs, follows the cursor itself, and uncloaks once its
content settles. A window's only tab still moves the window itself (see
Gestures).

## Merge protocol (native, `window_utils_plugin.cpp`)

- A tab shell publishes its strip, in screen pixels, as properties of its
  top-level window: `CBFileHub.TabStrip.v1` plus `.Left/.Top/.Right/.Bottom`.
  Dart reports the bounds through `setTabStripBounds`. Native code re-publishes
  them on `WM_WINDOWPOSCHANGED` and `WM_DPICHANGED`.
- `RunTabWindowDrag` runs on a worker thread with a 4 ms high-resolution
  timer:
  - It moves the window only when the cursor moves, using
    `SWP_ASYNCWINDOWPOS` so it never blocks on the UI thread.
  - It hit-tests the topmost window under the cursor via `EnumWindows` and the
    strip properties, with no IPC.
  - On entering a strip, it sends the label (`WM_COPYDATA`, `CBTE`). Moves,
    leaves and a 250 ms keep-alive are *posted* (`CBFileHub.TabMerge.v1`).
  - It cloaks the dragged window (DWM) while it is over a strip, as Chrome
    hides it.
  - On release over a strip, it sends the tab payload (`WM_COPYDATA`, `CBTD`).
    If the target accepts, the dragged window stays cloaked and gets
    `onTabWindowMerged`, then closes after unregistering. Otherwise it
    uncloaks.
- The target turns hovers into `onTabMergeHover`. That drives
  `ExternalTabDropController.hover`. The tab bar opens a gap there (neighbours
  slide aside, a ghost tab fills it). The gap stays open until the dropped tabs
  are in the bloc state, so the ghost and the real tab swap in one frame. A
  drop arrives as `onTabMergeDrop` and inserts through
  `AddTab.insertIndex`. A hover not refreshed for 800 ms is cleared, in case
  the dragging process died.

## Tab motion

Tabs have a fixed width, so `_TabSlotMotion` animates them with a transform
only (FLIP): when a tab's slot changes it slides over 180 ms from where it was
drawn, and new tabs scale and fade in. That covers reorder, close, the merge gap
and tear-off. Neighbours never relayout during the animation. Each tab is keyed
by id at the row level, so reorders keep tab state.

During a native drag the dragged tab follows the pointer horizontally. A copy is
painted above the row so neighbours slide under it, and it reorders once its
middle crosses a neighbour's slot. On release it settles into its slot. On
tear-off it fades out, and its neighbours close the gap once it is removed.

## Key files

- `cb_file_manager/windows/runner/window_utils_plugin.cpp`: drag loop and
  merge target.
- `cb_file_manager/lib/services/windowing/windows_native_tab_drag_drop_service.dart`:
  channel API.
- `cb_file_manager/lib/services/windowing/desktop_windowing_service.dart`:
  spare, registry, `show_window`.
- `cb_file_manager/lib/ui/tab_manager/desktop/scrollable_tab_bar.dart`:
  detach rule, anchor, strip bounds, tab motion.
- `cb_file_manager/lib/ui/tab_manager/desktop/external_tab_drop_controller.dart`

macOS and Linux keep the in-window "Move tab to window" overlay. The context
menu's *Move tab to new window / Move tab to window* works on every desktop
platform.
