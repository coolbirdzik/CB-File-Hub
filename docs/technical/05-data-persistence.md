# Data and Persistence

## Active storage

- **Database:** SQLite through `lib/models/database/database_manager.dart` and
  `lib/models/database/sqlite_database_provider.dart`.
- **Structured data:** tags, hierarchy, folder display preferences, thumbnails,
  albums, video libraries, network credentials, AI provider configuration, and
  related metadata use SQLite tables.
- **Legacy naming:** model files under `lib/models/objectbox/` remain as
  compatibility paths. `ObjectBoxDatabaseProvider` is an alias of the SQLite
  provider; do not introduce ObjectBox-specific behavior based on directory
  names.

## Preferences and secrets

- `lib/helpers/core/user_preferences.dart` bridges SharedPreferences
  bootstrap/legacy state and SQLite-backed preferences.
- Several UI surfaces retain direct SharedPreferences state for lightweight
  presentation settings and migrations.
- Local AI secrets use `flutter_secure_storage`; do not move secrets into plain
  preferences or logs.

## Domain consumers

- `lib/services/network_credentials_service.dart` persists network credential
  records through the active SQLite database layer.
- `lib/services/album_service.dart` and
  `lib/services/video_library_service.dart` persist media collections.
- `lib/services/ai/ai_provider_service.dart` persists provider configuration.
- Thumbnail and network-media services also maintain filesystem caches whose
  lifetime is separate from the database.

See the persistence graph in [system-map.md](../agent/system-map.md) and the
`persistence` entry in [feature-map.yaml](../agent/feature-map.yaml).

_Last reviewed: 2026-08-08_
