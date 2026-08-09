# Agent Graph — Core Execution Flows

These diagrams show runtime ownership and safety boundaries. They intentionally
omit low-value helper calls. Use `feature-map.yaml` for concrete source paths.

## Application startup

```mermaid
flowchart TD
    Entry[main.dart] --> Binding[Flutter and platform bindings]
    Binding --> Window[Window role and desktop configuration]
    Window --> Rendering[Frame, image cache, and MediaKit setup]
    Rendering --> GetIt[setupServiceLocator]
    GetIt --> Prefs[Initialize preferences and language]
    Prefs --> Data[Initialize SQLite, credentials, and tags]
    Data --> Heavy[Initialize thumbnails and albums]
    Heavy --> Mode{Window role}
    Mode -->|PiP| PiP[DesktopPipWindow]
    Mode -->|Main or secondary| App[CBFileApp]
    App --> Tabs[TabMainScreen]
```

Secondary windows can defer selected initializers until after their first
frame. Read `main.dart` before changing startup order; helpers under
`lib/config/` are not a substitute for verifying the active call path.

## Tab and folder navigation

```mermaid
flowchart LR
    User[User navigation] --> TabMain[TabMainScreen]
    TabMain --> TabEvent[TabManagerBloc event]
    TabEvent --> TabState[TabManagerState]
    TabState --> TabScreen[TabScreen]
    TabScreen --> Router{System or folder path}
    Router -->|Folder| Pane[TabbedFolderListScreen]
    Router -->|System| System[SystemScreenRouter]
    Pane --> FolderBloc[FolderListBloc]
    Pane --> Selection[SelectionBloc]
    FolderBloc --> FS[Filesystem and network services]
```

Provider context is part of the ownership contract. Menus, dialogs, overlays,
and detached windows that operate on a pane must receive that pane's BLoC
instance rather than resolving an unrelated ancestor.

## AI agent tool loop

```mermaid
flowchart TD
    Input[Chat input] --> Event[AiAgentBloc request event]
    Event --> Provider[AiProviderService]
    Provider --> Stream[Provider response stream]
    Stream --> Decision{Tool call?}
    Decision -->|No| Message[Finalize assistant message]
    Decision -->|Yes| Approval{Side effect?}
    Approval -->|Approval required| UserApproval[User approval UI]
    Approval -->|Read only| Execute[ToolExecutor]
    UserApproval -->|Approved| Execute
    UserApproval -->|Rejected| Result[Rejected tool result]
    Execute --> Result[Tool result]
    Result --> Provider
    Stop[Stop generation] --> Cancel[Cancel active stream and tool loop]
    Cancel --> Stable[Finalize running tool state]
```

Every async continuation must verify that it still belongs to the active
generation. Read-only labels do not override actual side effects; the tool
implementation and approval registry must agree.

## Cleaner scan, review, and deletion

```mermaid
flowchart TD
    Screen[CB Agent Cleaner screen] --> Scan[DiskCleanerService]
    Scan --> Worker[Full disk scan isolate]
    Worker --> Progress[Progress snapshots]
    Worker --> Tree[DiskTreeNode tree]
    Tree --> Classification[Rule-backed junk classification]
    Classification --> Selection[DiskTreeSelection]
    Selection --> Preview[Exact deletion preview]
    Preview --> Approval{Explicit approval}
    Approval -->|Recycle Bin| Trash[TrashManager]
    Approval -->|Permanent| Direct[Bounded direct deletion]
    Trash --> FileOps[WindowsFileOperations]
    FileOps --> Shell[Windows IFileOperation]
```

The scan can report usage without authorizing deletion. Safe ancestors,
application install folders, user data, and shared/unattributed folders do not
become junk merely because they are large.

## Cleaner App Insights

```mermaid
flowchart LR
    Inventory[Win32 and MSIX inventory] --> Merge[WindowsAppInventoryService]
    Usage[UserAssist and Prefetch evidence] --> Merge
    Scan[Measured disk scan roots] --> Analyzer[AppStorageAnalyzer]
    Merge --> Analyzer
    Analyzer --> Report[AppStorageReport]
    Report --> Cubit[CleanerAppInsightsCubit]
    Cubit --> View[CleanerAppsView]
    View --> Share{Explicit share with AI}
    Share --> Tool[get_current_app_storage]
```

Usage timestamps are evidence with confidence, not proof that an application
is unused. The AI tool is read-only and must redact paths unless the selected
application and sharing options permit them.

## Windows Shell context menu

```mermaid
flowchart TD
    Gesture[Right-click exact selection] --> Root[Build application root menu]
    Root --> Popup[Show popup immediately]
    Root --> Session[Request or reuse native Shell session]
    Session --> Key[Normalized paths plus Shift state]
    Popup --> Open{Third-party submenu opened?}
    Open -->|No| Idle[No native submenu expansion]
    Open -->|Yes| Init[loadContextMenuSubmenu]
    Init --> Native[WM_INITMENUPOPUP]
    Native --> Children[Return child sections]
    Children --> Popup
    Popup --> Invoke[invokeContextMenuCommand]
    Invoke --> Release[Invalidate or release session]
```

The cache is process-local and target-specific. Never persist native command
IDs or reuse them for another selection.

## Local GGUF inference

```mermaid
flowchart LR
    Settings[Local AI settings] --> Advisor[LocalAiAdvisorService]
    Advisor --> Runtime[GgufLlamaCppRuntime]
    Runtime --> Process[llama/llama-server.exe]
    Process --> Health[/health]
    Process --> Chat[HTTP chat completion]
    Runtime --> Reaper[Windows Job Object]
    Reaper --> Kill[KILL_ON_JOB_CLOSE]
```

The runtime is isolated in the `llama/` subfolder so Windows resolves the
system Vulkan loader instead of the unrelated app-local Vulkan DLL.

_Verified against repository baseline `7f40c2a` plus the working tree on
2026-08-09._
