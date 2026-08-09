## Navigation & State Management

- **TabShell** `ui/tab_manager/core/tab_main_screen.dart` hosts the tabbed experience via `TabManagerBloc` and `NetworkBrowsingBloc`.
- **TabLifecycle** `TabMainScreen.openPath(context, path)` dispatches `AddTab` events; tabs render through `TabScreen` composables.
- **Workspace Restore** `ui/tab_manager/core/tab_screen.dart` restores the last opened tab path on startup and persists active tab path changes when workspace restore is enabled.
- **Sidebar Pinning Actions** `ui/components/common/shared_file_context_menu.dart` and `ui/tab_manager/components/drive_view.dart` expose `Pin to Sidebar` and `Unpin from Sidebar` for filesystem paths.
- **Drawer State** `ui/widgets/drawer/cubit/drawer_cubit.dart` tracks pinned paths plus per-tab expansion state for `storage` and `pinned` sections.
- **Pinned Drawer Group** `ui/widgets/drawer/pinned_section_widget.dart` renders a dedicated `Pinned` section, separate from storage/drives.
- **PermissionsGate** On first frame, `PermissionStateService` checks storage/network permissions and pushes `PermissionExplainerScreen` if needed.
- **Mobile Actions** `ui/tab_manager/mobile/mobile_file_actions_controller.dart` coordinates action bars shared across file list and media galleries.
- **Selection Logic** `bloc/selection/` tracks multi-select state and exposes BLoC events for UI components.

Provider and lifecycle ownership are documented in the
[Agent State Ownership Graph](../agent/state/state-ownership.md). Consult it
before moving a menu, dialog, or overlay outside its pane's provider subtree.

_Last reviewed: 2026-08-08_
