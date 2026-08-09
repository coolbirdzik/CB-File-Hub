# Agent Graph — System Map

## Workspace boundaries

```mermaid
flowchart LR
    Root[Workspace root] --> App[cb_file_manager]
    Root --> SMB[mobile_smb_native]
    Root --> Build[justfile and scripts]
    Root --> Installer[installer]

    App --> Dart[Flutter and Dart application]
    App --> Win[Windows runner plugins]
    App --> Tests[Unit, widget, and integration tests]
    SMB --> FFI[libsmb2 FFI implementation]
    Build --> Runtime[llama.cpp runtime fetch and packaging]
```

- Run all `flutter` and `dart` commands from `cb_file_manager/`.
- Use the workspace-root `justfile` as the primary build and verification
  interface.
- `mobile_smb_native/` is a local path dependency, not a child folder of the
  Flutter package.
- `cb_file_manager/windows/llama/` is fetched build input and is not committed.

## Application runtime graph

```mermaid
flowchart LR
    Main[lib/main.dart] --> Bootstrap[Service and platform bootstrap]
    Bootstrap --> RootApp[CBFileApp]
    RootApp --> Tabs[TabMainScreen]

    Tabs --> TabBloc[TabManagerBloc]
    Tabs --> NetworkBloc[NetworkBrowsingBloc]
    Tabs --> Folder[FolderListBloc per pane]
    Tabs --> SystemScreens[SystemScreenRouter]

    Folder --> FileServices[Filesystem and metadata helpers]
    NetworkBloc --> NetworkServices[SMB, FTP, and WebDAV services]
    SystemScreens --> Features[Gallery, tags, settings, cleaner, and AI]

    FileServices --> SQLite[SQLite]
    Features --> SQLite
    NetworkServices --> SMBPlugin[mobile_smb_native]
    Features --> Channels[Windows MethodChannels]
    Features --> Llama[llama-server subprocess]
    Channels --> Runner[windows/runner C++]
```

## State and dependency boundaries

```mermaid
flowchart TB
    GetIt[GetIt service locator] --> LongLived[Long-lived services]
    Provider[Provider] --> Theme[ThemeProvider]
    BlocProviders[BlocProvider tree] --> AppBlocs[Application and tab BLoCs]
    Screen[Screen ownership] --> ScreenCubits[Feature cubits and notifiers]

    LongLived --> DatabaseManager
    LongLived --> DiskCleanerService
    LongLived --> LocalAiAdvisorService
    LongLived --> TabActivityManager

    AppBlocs --> TabManagerBloc
    AppBlocs --> NetworkBrowsingBloc
    ScreenCubits --> FolderListBloc
    ScreenCubits --> AiAgentBloc
    ScreenCubits --> CleanerAppInsightsCubit
```

Use `lib/core/service_locator.dart` to verify which services are process-wide.
Do not infer that every class named `Service` is registered with GetIt.

## Persistence boundaries

```mermaid
flowchart LR
    Domain[Tags, albums, libraries, credentials, provider config] --> DBM[DatabaseManager]
    DBM --> SQLiteProvider[SqliteDatabaseProvider]
    SQLiteProvider --> SQLite[(SQLite database)]

    Startup[Theme, language, bootstrap and legacy preferences] --> SharedPrefs[SharedPreferences]
    UserPrefs[UserPreferences] --> SharedPrefs
    UserPrefs --> SQLite

    Secrets[Local AI secrets] --> SecureStorage[flutter_secure_storage]
    Cache[Thumbnails and network media] --> DiskCache[Filesystem caches]
```

Files under `lib/models/objectbox/` retain legacy names for compatibility, but
the active database provider is SQLite. Never infer the active backend from a
legacy import path alone.

## Verification boundary

```mermaid
flowchart LR
    Change[Change] --> Format[Format check]
    Format --> Analyze[Analyze]
    Analyze --> Unit[Unit and widget tests]
    Unit --> E2E[Windows E2E when applicable]
    E2E --> Build[Windows build when native or packaging changes]
```

The CI order is format, analyze, unit tests, E2E, then build. Focused checks may
be used during iteration, but they do not redefine the final risk boundary.

## Graph-first coding loop

```mermaid
flowchart TD
    Task[Source-code task] --> Inspect[Inspect agent graph and source]
    Inspect --> Impact{Graph impact?}
    Impact -->|None| Code[Implement]
    Impact -->|Changed| Delta[Present graph delta]
    Delta --> Approval{User approval}
    Approval -->|Revise| Inspect
    Approval -->|Approved| Graph[Update canonical graph]
    Graph --> Code
    Code --> Verify[Verify]
    Verify --> Match{Graph, code, and checks agree?}
    Match -->|Yes| Done[Finish]
    Match -->|No, same approved scope| Code
    Match -->|No, graph boundary changed| Delta
```

Reading and classifying graph impact is mandatory for source-code tasks. User
approval is required only when nodes, edges, ownership, contracts, scope,
destructive behavior, or safety invariants change. Failures within the approved
scope loop through implementation and verification without another approval.

_Verified against repository baseline `7f40c2a` plus the working tree on
2026-08-09._
