# Tab Windows: Tear-off and Merge (Windows)

**Purpose**: Chrome-style tab windows. Drag a tab out of the tab strip to open
it in a new window that follows the cursor; drop a window's tab on another
window's tab strip to move it there.

## Architecture on Windows

New browser windows opened from the app share one Flutter engine by default.
Each gets its own Windows window, view, tab manager and navigator. The engine
stays alive while any of these windows is open. Set `CB_SHARED_ENGINE_WINDOWS=0`
before launching the app to use separate processes for browser windows.

Native tab tear-off, session transfers, torrent options, dedicated video, PiP
and progress windows use separate processes. Shared-engine browser windows
currently support tab reordering within their own window. Native drag-and-drop
between windows uses the separate-process tab transfer path. Process isolation
also gives each separate engine its own ANGLE D3D11 display.

`WindowsTabWindowLaunch` sends startup tabs over an authenticated loopback
connection so large session snapshots can exceed Windows environment variable
limits. The destination applies window placement and shows the rendered frame
before confirming startup. The source keeps its tabs until confirmation.

Rendering on Windows defaults to Impeller (`PreferredImpellerSwitch`;
`CB_WINDOWS_RENDERER=skia` for comparisons — under the guard below Skia lost
its EGL context and stopped drawing). `InstallD3D11ThreadingGuard`
(`windows/runner/d3d11_threading_guard.cpp`) makes ANGLE create its D3D11
devices with `D3D11_CREATE_DEVICE_PREVENT_INTERNAL_THREADING_OPTIMIZATIONS`:
the NVIDIA driver's internal worker threads crashed (`nvwgf2umx`) while a
video-thumbnail grid scrolled, under either renderer.
`CB_D3D11_DRIVER_THREADS=1` restores the driver default for comparison, and
`CB_FRAME_STATS=1` prints build/raster frame percentiles every 5 s.

- `WindowsEngineHost` (`lib/services/windowing/windows_engine_host.dart`)
  handles startup and shutdown over `cb_file_manager/engine_windows`. Each
  new process gets its own options, and native plugins register with its engine.
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
- Peer and registry sockets discover other windows and carry tab payloads.
  The HWND-based preview and merge protocol works across processes. New tab
  windows start on demand, and keeping a hidden spare resident is disabled.
- Each engine runs its UI isolate on its own thread
  (`UIThreadPolicy::RunOnSeparateThread`, `PreferredUIThreadPolicy()` in
  `windows/runner/utils.cpp`). Merged threads would put every window's Dart on
  the one platform thread: a busy window would stall the others, and the drag
  worker's `WM_COPYDATA` enter/drop/reveal sends (1 s timeouts) would wait on
  that Dart work, so a merge could fall back to a detach. Flutter logs that it
  will drop the separate-thread option; it is still present on master (October
  2026). Launch with `CB_MERGED_UI_THREAD=1` to run the merged policy and check
  tab drag, merge, tear-off, the context menu and video playback against it.
- The source calls `AllowSetForegroundWindow` before opening a destination or
  handing off a drag. The drag loop releases its active flag on mouse-up while
  the preview can stay visible until the destination is ready.
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
- Each visible window owns its process lifetime. A closed window can keep its
  process alive while a file operation or model download finishes. Torrent
  activity uses the existing aria2 ownership lock and takeover mechanism.
- Each process runs SQLite on a worker. Connections share the database file
  using WAL and a busy timeout. The window registry can be re-elected by a
  surviving window after the registry owner exits.
- E2E mode does not initialize the engine host or create spare engines. Unit/widget
  coverage includes launch-channel contracts and serialized tab transfer. It does
  not prove real window dragging, DPI behavior or native-plugin runtime parity.

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
3. On release (`onTabTearOffEnded`):
   - **empty space**: start the destination at the preview's physical client
     origin. The native preview stays briefly while the destination renders.
     The source closes the moved tabs when the destination acknowledges it.
   - **another window's strip**: the source sends the tabs there
     (`WM_COPYDATA`) and closes them after the target accepts.
   - **the source's own strip**: the tab returns and moves to the gap it
     opened. Escape cancels.

When the preview cannot start, the destination is launched directly from the
drag. A window's only tab still moves the window itself (see Gestures).

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
