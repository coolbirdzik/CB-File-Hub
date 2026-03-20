## Layer Catalogue

| Layer         | Representative Paths                                                           | Highlights                                                                                        |
| ------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| Configuration | `config/theme_config.dart`, `config/app_theme.dart`, `config/languages/`       | Minimal theme tokens, color scheme, localization delegates, runtime language switching.           |
| Utils         | `utils/app_logger.dart`                                                        | Centralized logging framework (NEVER use `print()` in production).                                |
| Helpers       | `helpers/core/filesystem_utils.dart`, `helpers/media/`, `helpers/tags/`        | Filesystem traversal, media caches, tag batch operations, platform-specific utilities.            |
| Native Plugins| `windows/runner/`                                                              | Custom Windows C++ plugins for high-performance tasks (Thumbnails, Shell integration).            |
| Services      | `services/album_*`, `services/network_browsing/`, `services/streaming/`        | Long-running tasks, isolates, network adapters (FTP/SMB/WebDAV), streaming session orchestration. |
| UI Screens    | `ui/screens/media_gallery/`, `ui/screens/permissions/`, `ui/screens/settings/` | Feature-specific views with responsive layouts and shared action patterns.                        |
| UI Components | `ui/components/`                                                               | Reusable cards, buttons, bottom sheets, PiP controls, gallery tiles.                              |
| Widgets       | `widgets/`                                                                     | Leaf widgets consumed across multiple screens (e.g., progress indicators).                        |
| Data Models   | `models/` + `objectbox-model.json`                                             | ObjectBox entities for files, tags, preferences, plus DAO helpers.                                |

_Last reviewed: 2026-03-07_
