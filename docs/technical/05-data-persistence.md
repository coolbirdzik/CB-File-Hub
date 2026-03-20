## Data & Persistence

- **Database**: ObjectBox (`cb_file_manager/lib/models/objectbox/` and `objectbox.g.dart`) stores:
    - **Tags**: `FileTag` entities.
    - **Metadata**: `Album`, `AlbumFile`, `VideoLibrary`, `VideoLibraryFile`.
    - **Network**: `NetworkCredentials`.
    - **Preferences**: `UserPreference` entities for synced settings.

- **Hybrid Preferences**: `cb_file_manager/lib/helpers/core/user_preferences.dart` implements a hybrid strategy:
    - **Bootstrap**: Uses `SharedPreferences` to store critical startup flags like `use_objectbox_storage`.
    - **Storage**: Uses ObjectBox as the primary backend for all other settings if enabled, falling back to `SharedPreferences` if necessary.

- **Settings Management**:
    - **View State**: Persists `view_mode`, `sort_option`, `grid_zoom_level`.
    - **Preview Pane**: Stores `preview_pane_visible` and `preview_pane_width` for desktop layouts.
    - **Navigation**: Saves `last_accessed_folder`, `recent_paths`.
    - **Sidebar**: `sidebar_pinned_paths` maintains the user's pinned directories.
    - **Workspace**: `remember_tab_workspace`, `last_opened_tab_path`, and `drawer_section_states_by_tab` restore the previous session state.

- **Credential Vault**: `cb_file_manager/lib/services/network_credentials_service.dart` securely manages SMB/FTP/WebDAV authentication details via ObjectBox.

- **Caching**: 
    - **Thumbnails**: `cb_file_manager/lib/helpers/media/video_thumbnail_helper.dart` and `folder_thumbnail_service.dart` manage disk and memory caches.
    - **Network**: `network_file_cache_service.dart` handles temporary storage for streamed content.

_Last reviewed: 2026-03-07_
