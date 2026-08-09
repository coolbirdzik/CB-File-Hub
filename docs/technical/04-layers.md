# Layer Catalogue

| Layer | Representative paths | Responsibility |
| --- | --- | --- |
| Bootstrap | `main.dart`, `core/service_locator.dart` | Window roles, initialization order, root widget, long-lived service registration. |
| Configuration | `config/`, `providers/theme_provider.dart` | Feature flags, theme selection, language controller, localization implementations. |
| State | `bloc/`, `ui/screens/folder_list/*_bloc.dart`, `ui/tab_manager/core/tab_manager.dart` | Application, tab, pane, selection, AI, and feature state machines. |
| Helpers | `helpers/core/`, `helpers/files/`, `helpers/media/`, `helpers/tags/` | Cross-cutting filesystem, native-wrapper, media-cache, and tag operations. |
| Services | `services/` | Persistence consumers, networking, streaming, AI providers, local runtimes, and long-running work. |
| Persistence | `models/database/`, `helpers/core/user_preferences.dart` | SQLite abstraction plus SharedPreferences-backed bootstrap and migration state. |
| UI | `ui/screens/`, `ui/components/`, `ui/widgets/`, `ui/tab_manager/` | Feature surfaces, reusable interaction components, and the tab shell. |
| Native plugins | `windows/runner/` | Windows Shell, file operations, app inventory/icons, thumbnails, drag/drop, and window behavior. |
| Local FFI plugin | `../mobile_smb_native/` | SMB/CIFS access through libsmb2. |
| Verification | `test/`, `integration_test/`, `tool/` | Unit/widget coverage, Windows E2E, parallel runner, reports, and dashboard. |

The repository contains compatibility paths and legacy names. In particular,
`lib/models/objectbox/` model imports do not mean ObjectBox is the active
database backend. Follow the [Agent Feature Map](../agent/feature-map.yaml) from
an entry point to its active implementation.

_Last reviewed: 2026-08-08_
