# CB File Hub — Technical Overview

## Purpose

- **Audience:** maintainers who need a short mental model of the application.
- **Agent routing:** use [`docs/agent/index.md`](../agent/index.md) for
  source-linked feature and contract graphs.
- **Path convention:** paths below are relative to `cb_file_manager/`.

## System overview

- **Application:** cross-platform Flutter file manager with desktop-focused
  Windows integrations.
- **Entry point:** `lib/main.dart` owns active startup wiring, window roles,
  service initialization, and the root application.
- **Shell:** `ui/tab_manager/core/tab_main_screen.dart` owns the tab-based user
  experience; navigation is not conventional route-first Flutter navigation.
- **State:** BLoC, Provider, screen-owned notifiers, and GetIt coexist with
  different ownership lifetimes.
- **Persistence:** SQLite is the structured data backend. SharedPreferences
  remains for bootstrap, UI state, and migration paths.
- **Native boundaries:** Windows integrations use MethodChannels; SMB/CIFS uses
  the local `mobile_smb_native` FFI package.
- **Local AI:** GGUF inference launches a bundled `llama-server.exe` subprocess
  and communicates over HTTP.

```text
lib/
├── bloc/                     # Cross-feature BLoCs and cubits
├── config/                   # Theme, language, constants, and helpers
├── core/                     # Service locator and application-wide wiring
├── helpers/                  # Filesystem, media, tags, and native wrappers
├── models/                   # Domain models and database abstraction
├── services/                 # Business logic, runtimes, and long-running work
├── ui/                       # Screens, components, and tab manager shell
├── utils/                    # Cross-cutting utilities and logging
└── main.dart                 # Active startup sequence and root widget
```

See the [system map](../agent/system-map.md) for the runtime graph.

_Last reviewed: 2026-08-08_
