# AI Agent

## Purpose

The AI Agent adds a conversational assistant to CB File Hub for natural-language file search, file inspection, tag lookup, and guarded file operations. It is implemented as both a full chat tab and a right-side panel that can sit beside the current file browser tab.

## Entry Points

- **Drawer AI Chat tab**: opens `#ai-chat` through `SystemScreenRouter` and renders `AiChatScreen`.
- **Desktop side panel**: toggled from the tab shell and rendered by `AiSidePanel` beside the active file browser content.
- **Settings**: `AiSettingsSection` manages provider configuration inside the settings screen.

The side panel is scoped to the active tab. `AiPanelController` owns one `AiAgentBloc` per tab so chat state survives opening and closing the panel, and the panel closes automatically when the active tab changes.

## Panel Layout

- The side panel appears on the right side of the tab content.
- The panel width is resizable from the left edge.
- Width is clamped between `AiPanelController.minPanelWidth` and `AiPanelController.maxPanelWidth`, with an additional responsive maximum based on the current window width.
- The committed panel width is persisted in SharedPreferences under `ai_side_panel_width`.
- The conversation-history column inside the panel has its own resize handle and local width state.

## Provider Configuration

Provider records are stored in the `ai_providers` SQLite table through `AiProviderService`.

Supported API types:

- **OpenAI Compatible**: uses the `/v1/chat/completions` contract. This can support OpenAI, OpenRouter, Ollama, LM Studio, or similar endpoints.
- **Anthropic**: uses the Anthropic Messages API.

OpenAI-compatible providers now support two authentication modes:

- **API Key**: direct bearer key against the configured endpoint.
- **Codex OAuth**: reuses the local `codex login` / ChatGPT credential on the same machine.

Provider settings include:

- Name
- API type
- Authentication mode
- API key
- Endpoint
- Default model name
- Temperature
- Max tokens
- Optional system prompt
- Timeout seconds
- Max retries
- Enabled state
- Priority

`AiProviderService` keeps provider instances cached by ID, sorts enabled providers by priority, tracks provider health, skips providers that are temporarily down, and falls back to the next enabled healthy provider for non-streaming chat requests. The final answer path uses streaming when possible and falls back to a normal chat request if streaming fails.

For Codex OAuth mode, the runtime delegates requests to the local `codex exec` CLI in read-only mode and reads available models from `~/.codex/models_cache.json`. The settings dialog can launch `codex login` so the user can complete the ChatGPT sign-in flow outside the app.

Selecting Codex or editing a Codex provider automatically loads its model list.
Choose the default model from that list; Codex has no free-text model input.
An empty list or discovery error keeps the picker and offers a refresh. Saving
requires a listed model, and a saved model absent from a refreshed list must be
selected again. Other provider types keep manual model entry when discovery
is unavailable.

The chat UI loads model catalogs from every enabled provider and groups them by provider name in the model selector. The provider-level model saved in settings is only the default selection for new chats and fallback resolution when a provider cannot return a remote model list.

## Conversation Model

`AiAgentBloc` owns the runtime state for each conversation:

- Message list
- Loading and error state
- Active provider ID
- Selected provider ID
- Selected model name
- Current workspace path
- Search scope
- Thinking text
- Tool activity log
- Pending approval request
- Active conversation ID
- Conversation summaries

`AiChatHistoryService` persists conversations in SharedPreferences:

- `ai_conv_index`: conversation summaries
- `ai_conv_{id}`: messages for a conversation
- `ai_chat_history`: legacy single-conversation key migrated on first load

Conversation summaries also store a normalized workspace path. When the current AI workspace path changes, the BLoC first tries to reopen the most recently updated conversation for that exact path. If none exists, it starts a new empty conversation for that workspace path.

Only user and assistant messages that are no longer loading are persisted. Each conversation is capped at 200 messages. Conversation titles are derived from the first user message.

User messages can be edited inline from the chat bubble action. Editing a user message removes that message and all later messages, then sends the edited prompt again with the original referenced files. This keeps the visible conversation consistent with the model context instead of leaving stale assistant replies after an edited prompt.

When a conversation is opened or switched, the chat viewport jumps to the bottom by default so the latest exchange is visible immediately.

When the message list has focus, keyboard scrolling works like this:

- `Home`: jump to the top
- `End`: jump to the bottom
- `PageUp`: scroll up by roughly one viewport
- `PageDown`: scroll down by roughly one viewport

Text fields keep their normal key behavior because the shortcuts are handled only by the focused message viewport.

## Workspace Context

The agent receives the current browser path through `UpdateCurrentPath`. In the side panel, `TabScreen` keeps this path synchronized with the active non-system tab.

Search scopes are defined in `SearchScope`:

- Current folder
- Recursive search
- Tagged files
- All drives
- Video library
- Album

`FileContextBuilder` builds structured file context from the selected scope. It includes file paths, names, extensions, sizes, modified dates, created dates when available, categories, tags, and limited text previews for supported text files.

Context limits:

- Up to 500 files per context build.
- Text files over 1 MB are not read.
- Text previews are limited by `ContentReader.maxChars`, defaulting to 2000 characters.
- `ContentReader` uses UTF-8 first, then Latin-1 fallback, with a small LRU cache.

When the assembled provider prompt grows too large, `AiAgentBloc` automatically compacts older turns into a bounded plain-text summary and keeps the most recent conversation turns verbatim. This runs before provider calls and uses a more aggressive limit for the final streamed answer path.

## Referenced Files

Users can drag files into the chat input. The input stores referenced file paths separately from the typed message.

For referenced files:

- Text files are auto-read and included in the API message.
- Non-text files are listed as binary references with metadata guidance.
- The agent prompt tells the model not to read referenced text files again.
- The agent prompt tells the model to use metadata only for images, videos, audio, PDFs, archives, executables, and other binary data.

## Tools

The agent uses text tool-call blocks parsed by `ToolExecutor`:

```text
<tool_call>
{"name": "tool_name", "arguments": {"arg1": "value"}}
</tool_call>
```

Supported tools:

- `list_directory`: list files, folders, or available drives.
- `search_files`: recursively search by filename or extension.
- `read_file`: read text files up to safe limits, and the text of PDF, Office (docx/xlsx/pptx), OpenDocument, EPUB and RTF documents, with the line numbers `search_content` reports.
- `write_file`: create, overwrite, or append text files.
- `delete_file`: move one or more files to the recycle bin.
- `get_file_info`: return metadata for a file or directory.
- `run_command`: execute a shell command with timeout and blocking rules.
- `search_by_tag`: find files with a tag globally or within a path.
- `get_file_tags`: list tags attached to one file.
- `list_all_tags`: list all known tags.
- `search_content`: find files by what they contain. Words match anywhere in a file, ignoring case and diacritics (`"quoted phrase"` stays whole); `match: any` ranks partial matches. It reads text files and the text of PDF, Office, OpenDocument, EPUB and RTF documents, and returns one ranked item per file with snippets. It runs in Rust (`cb_native` `content.rs`/`doctext.rs`) on every pool thread, so a whole drive fits its bounds (400k entries, 2 GiB read, 45 s); without the native library a Dart isolate searches with smaller bounds and no PDF reader. Cloud placeholders (OneDrive, iCloud) are never read, so searching does not download them; `AppData` and system folders right below a drive root are skipped unless the search starts inside one. Anything skipped (scanned PDFs without a text layer, legacy .doc/.xls/.ppt, oversized files) is listed in `warnings` and makes `scope_complete` false.
- `select_cleaner_scan_items`: select exact paths from the current Cleaner scan for review, without deleting files. Read `get_current_cleaner_scan` first and pass its `scan_id`; `replace: false` adds to existing checked targets.

After a fresh Disk usage scan, **Quick review** explains what the data appears to be and whether to keep it or consider removing it. Every click starts a new conversation; previous reviews remain in history, and follow-up chat stays in the new conversation. It shows short CLEAN/REVIEW/KEEP recommendations beside the tree without selecting or deleting files. Users choose targets themselves, then use the existing review and cleanup confirmation controls. Explicit chat requests to select targets still use the scan identity and safety checks.

The interactive walkthrough uses `inspect_cleaner_scan_item` to expand, scroll to and highlight a real scanned row before analyzing it. `set_cleaner_scan_item_analysis` then displays a CLEAN/REVIEW/KEEP badge on that row and a reason in the adjacent CB Agent analysis pane. Assessments can be clicked to reveal their row again without changing checks. Only scanner-marked safe junk can be labelled CLEAN and automatically checked; focus alone never selects a cleanup target. Each interaction returns a fresh `scan_id` for the next step. Changing the scan invalidates earlier inspections and assessments. Completion, failure or Stop clears the live inspecting indicator.

In **Apps**, **View files** opens the storage locations linked to the selected
application; the same action beside a storage location opens it directly.
The preview lists real filenames, paths and file sizes, with folder navigation,
Back, refresh and visible read errors with Retry. It lists one directory at a
time on Rust threads or a Dart isolate, including hidden/config files and
omitting links. Directory sizes are not recursively recalculated. Locations
retain their confirmed/possible/shared attribution; application data is not
automatically junk. Only a confirmed cleanable location offers **Review cleanable
data**, which passes that exact rule-backed root to the existing cleanup preview
and confirmation flow. Browsing does not select deletion targets.

Cleaner deletion runs in a background isolate. Permanent deletion uses the
optional `cb_native` `deletion.rs` job with up to eight Rust workers and one
outcome per approved path, including the OS error on failure; missing native
support keeps the asynchronous Dart implementation. Recycle Bin moves continue
through Windows Shell. Progress is throttled and never moves backwards within
a batch. After deletion, the scan tree is updated in short work slices and
dashboard diagnosis is prepared in an isolate before returning to the results.

**Smart Clean** is the Cleaner's start page on Windows and macOS. One scan
checks regenerable junk (`CleanerQuickClean`,
`lib/services/disk_cleaner/cleaner_quick_clean.dart`): temporary files untouched
for a week, browser and app caches inside folders named as caches, thumbnail
caches and crash dumps/error reports untouched for a day, plus the narrowly
scoped caches in `CleanerCacheRules` (`cleaner_cache_rules.dart`). It skips the
AppData-wide `*.log` rules (LevelDB and IndexedDB use `*.log` files) and
database and service-worker storage folders. Results are grouped by category with checkboxes, and the
selection is moved to the Recycle Bin (Trash) in one click.

The additional categories are:

| Category | Scope | Effect of cleaning |
| --- | --- | --- |
| Windows shader cache | `%LOCALAPPDATA%/D3DSCache`, files unchanged for at least seven days | Shaders compile again; a game may launch more slowly or stutter initially. No Windows Update, WinSxS, installer cache, driver files or Prefetch is added to Smart Clean. |
| Package download caches | Default npm `_cacache`, pip cache, Cargo `registry/cache`, NuGet HTTP `v3-cache`, Composer `files`; unchanged for at least seven days | Later installs/restores may need internet or rebuild wheels. Installed libraries and source trees stay in place. |
| Electron app caches | Explicit cache subfolders in the default profiles of Discord/stable/PTB/Canary, Slack, VS Code/stable/Insiders, Cursor, Windsurf, Notion, Obsidian, Postman, Figma, Signal and GitHub Desktop; unchanged for at least one day | HTTP, compiled JavaScript and GPU caches rebuild. Cookies, preferences, Local/Session Storage, IndexedDB, Service Worker and CacheStorage remain outside the rules. |
| Old Xcode build files (macOS) | Generated build products/intermediates, `Index.noindex` and shared module/compilation/SDK/symbol caches inside the default DerivedData; unchanged for at least seven days | Build and indexing may take longer. Close Xcode and stop builds first. Sources, `SourcePackages`, `.xcarchive` and `.dSYM` files are kept. |

The Xcode rule uses a scoped discovery pass on the scan isolate. It enumerates
only immediate DerivedData project folders and known output locations; it never
turns the whole DerivedData root into a Smart Clean target. Both the native and
Dart scan paths reject archives, dSYMs and package checkout paths, and cleanup
rechecks those exclusions. Other scanners do not reinterpret the scoped rule as
a whole-tree rule. Custom DerivedData locations, simulator data, device support
and archives are not included. Apple documents that
[DerivedData can be recreated from sources](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html)
and that [distribution dSYMs should be retained](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information).

**Old downloads — review only** is a separate inspection panel on Windows and
macOS. The same scan lists the default Downloads folder's files unchanged for
at least 90 days, retaining at most the 200 largest unique candidates. It shows
the exact path, size and last-modified date, and can open the containing folder.
Last-modified time is explicitly not evidence of when a file was last opened or
whether it is unused. These typed review candidates never enter cleanup groups,
selection counts or clean callbacks, and remain available after cleanup. Their
category is `reviewOnly`: it cannot add deletion allowlist prefixes or mark disk
tree nodes as junk, and the cleanup service rejects it even if an item is forged
as a user selection. This panel has no checkbox or delete action.

Package downloads and Electron caches are supported on Windows and macOS.
The rules use default cache locations; custom locations and Electron session
partitions are left alone. Electron scanning never walks an entire profile or
all of AppData. Editor `CachedData` is included for the VS Code family. Lock
files are excluded, and selection deduplicates paths across categories.
Users must close the affected apps/games and finish package installs or builds
before cleaning; age checks alone cannot prove a cache is idle. The existing
cleanup pipeline skips locked files. The source rows distinguish caches that
rebuild from package archives that may need downloading again.

The cache contracts come from the upstream documentation:
[npm cache](https://docs.npmjs.com/cli/v11/commands/npm-cache/),
[pip caching](https://pip.pypa.io/en/stable/topics/caching/),
[Cargo home](https://doc.rust-lang.org/cargo/guide/cargo-home.html),
[NuGet cache folders](https://learn.microsoft.com/en-us/nuget/consume-packages/managing-the-global-packages-and-cache-folders),
[Composer cache configuration](https://getcomposer.org/doc/06-config.md#cache-files-dir),
[Electron session cache versus storage](https://www.electronjs.org/docs/latest/api/session#sesclearcache),
and [Microsoft's D3DSCache specification](https://microsoft.github.io/DirectX-Specs/d3d/ShaderCache.html).
In particular, NuGet's global packages are used directly by PackageReference
projects, while its HTTP cache contains download responses. Smart Clean keeps
`.nuget/packages`, `node_modules`, pnpm/Yarn stores, pub cache, virtualenvs,
`site-packages`, Cargo sources/bin, Gradle caches and Maven's repository out of
its selection. The broader opt-in `dev_cache` category is not enabled for Smart
Clean.

Each category is split into sources: the app that made the files and what they
are (`CleanerItemOrigins`, `lib/services/disk_cleaner/cleaner_item_origin.dart`).
The app comes from the executable a crash dump or WER report names, the owner
hint of the cleaner rule the path falls under, a known vendor folder (Firefox,
other Chrome profiles, macOS bundle IDs) or a known `%TEMP%` scratch-folder
prefix. Then the apps installed on the machine (the same Win32/MSIX or macOS
inventory as App Insights, read once per Cleaner screen alongside the scan,
waited for at most 3 s) name the rest through `CleanerInstalledApps`
(`lib/services/disk_cleaner/cleaner_installed_apps.dart`): an install folder
holding the file, then an exact folder or file name (`TeraBox`,
`IDM_Setup_Temp` by acronym, `…WarpSetup.exe` by a camelCase word). Matching is
deliberately exact, unlike App Insights' leftover `AppTokenIndex`: each app
contributes one brand word, names two apps share are dropped, generic folder
words never match, executable names match only whole names, and file names only
count directly under a %TEMP% top folder. Names the classifier already knows are
linked to the installed entry through their executables. Matched sources show
the app's own icon and an "Installed" tag; not being matched never means
uninstalled, since the inventory misses portable and CLI tools. Otherwise the
folder name is shown as a folder, and random names (GUIDs, hex IDs, `tmpXXXX`)
stay "unknown app" rather than being guessed. The kind (web,
compiled-script or GPU cache, temp file, installer leftover, log, crash report,
thumbnail database) comes with what removing it costs: rebuilt automatically,
no longer used, only for troubleshooting, or cannot be restored. Each source has
its own checkbox and file list; a category's checkbox is tristate. Past ten
sources the smallest are folded into one row. Origins are display-only and are
derived from the path after the scan, so the scan, the Rust rules and
`CleanerQuickClean` eligibility are unchanged.

The Recycle Bin is read while the rule scan runs, from the `$I` metadata files
(`streamRecycleBinEntries`), not through Shell COM: Shell materialises the
whole bin first (over 14 s just to count a 12k-item bin), the direct read takes
about 0.3-1.7 s. Shell is only used when the direct read finds nothing. The
Rust junk scan widens the walk pool to every base thread, since each rule
group is a single walk; a %TEMP% with ~9k folders went from 3.4-7.8 s to
0.8-1.8 s. Locked files are
skipped without prompting. On Windows the Recycle Bin is listed as an extra,
unchecked group; including it asks for confirmation because it is deleted
permanently. State lives in `CleanerSmartCleanCubit`
(`lib/bloc/cleaner_smart_clean/`).

Cleaner is also available on macOS. Its volume picker uses local writable
volumes and prefers the APFS Data mount, avoiding duplicate System/Data scans.
Both the Rust scanner and a portable Dart fallback support POSIX paths and
symlinks; path identity preserves case and recognises Data-mount aliases.
macOS rules cover browser caches, application caches, diagnostic reports and
opt-in developer caches. Rule-based cleanup stays within those resolved user
paths; application data and personal files are excluded. Trash moves use
Foundation `FileManager.trashItem` on a utility queue and report each failed
path. The result screen offers Finder Trash instead of Windows bin deletion.
Apps inventory/uninstall remains Windows-only. Leftover app data (folders of
uninstalled or outdated apps) works on Windows, macOS and Linux and moves
folders to the Trash on macOS and Linux; on Linux it is the only Cleaner page.
Full Disk Access restrictions appear as scan coverage gaps;
Cleaner does not change macOS permissions.

**Quick review** groups retained scan entries by scope, scanner category, known cause and file type. Known categories, causes, types and folders receive immediate explanations from scan metadata. AI reviews at most 24 of the largest unrecognized file groups, with at most eight groups per prompt and four calls per run, further bounded by the context window. Valid partial answers are saved, including completed entries in truncated JSON. Invalid output is not retried automatically: missing verdicts receive conservative scan-based REVIEW advice. A provider failure ends AI calls and completes the overview using scan metadata. The pane labels the source of each recommendation, and the summary distinguishes metadata groups from AI recommendations and notes scan coverage limits. No file contents are read, no group verdict selects files, and existing user selections remain intact. Metadata batches yield for UI frames and Stop. Stop and scan invalidation retain accepted progress; Retry resumes unfinished groups. The GGUF runtime uses direct responses for these short classification calls; normal chat keeps its existing reasoning settings. This is preliminary guidance, not an exhaustive file inspection. Cleanup still requires user confirmation.

To explain *why* a drive is full, `get_current_cleaner_scan` reports drive used vs. scanned space (unaccounted space usually means restore points or folders the scan could not read), top-level shares, space hotspots (the most specific locations of at least 0.5% of the scan), known Windows space causes, file-type totals, measurement gaps and old large items. Known causes come from `CleanerSpaceInsights` (`lib/services/disk_cleaner/cleaner_space_insights.dart`): hibernation/page files, restore points, Windows.old, WinSxS, Installer cache, WSL/Docker/VM disks, developer caches, node_modules, AI models, games, cloud-synced folders, phone backups, Outlook data, Downloads and personal folders. Each cause has an explanation, a safe way to reclaim the space and a starting CLEAN/REVIEW/KEEP verdict. These are explanations only and never selection or deletion rules. Two read-only tools let the agent investigate further in the in-memory tree without disk access: `explore_cleaner_scan` (drill down by path, depth 1-3) and `search_cleaner_scan` (by name, extension, type group, size or kind). When CB Agent is opened from the Cleaner screen (`#cb-agent-cleaner`), the cleaner guide is included in its system prompt.

Tool execution is iterative. The agent can call tools, receive tool results, and continue for up to `ToolExecutor.maxToolCalls` rounds before it must produce a final answer.

## Approval And Safety

These tools always require user approval before execution:

- `run_command`
- `write_file`
- `delete_file`

The BLoC combines dangerous tool calls from one model response into a single approval request. The UI shows an `ApprovalCard`, then resumes execution only after `ApproveAction` or `RejectAction`.

Safety behavior:

- `delete_file` moves files to the recycle bin instead of permanently deleting them.
- `run_command` has a 15-second timeout.
- `ToolExecutor` blocks destructive command patterns such as recursive force deletion, disk formatting, shutdown, reboot, service stopping, registry deletion, and similar commands.
- Binary files are not read as text.
- Large files are rejected or truncated depending on the operation.
- Tool output is truncated before being sent back to the model.

## Search Results

When the model finds files, it should return a natural-language explanation plus a JSON result block:

```json
[{"path": "C:\\exact\\path\\file.mp4", "relevance": 90, "explanation": "reason"}]
```

`AiAgentBloc` parses this block into `AiSearchResult` objects and strips the JSON from the visible chat bubble. The UI renders parsed results as `FileResultCard` entries with actions to open the file location, open the containing folder, or open externally.

## UI Components

Main files:

- `lib/ui/screens/ai_chat/ai_chat_screen.dart`: full tab chat experience.
- `lib/ui/screens/ai_chat/ai_side_panel.dart`: right-side panel experience.
- `lib/ui/screens/ai_chat/ai_panel_controller.dart`: side-panel lifecycle, per-tab BLoCs, and persisted panel width.
- `lib/ui/screens/ai_chat/components/chat_input_bar.dart`: text input, suggestion chips, drag-and-drop references.
- `lib/ui/screens/ai_chat/components/chat_message_bubble.dart`: message rendering.
- `lib/ui/screens/ai_chat/components/conversation_list_panel.dart`: saved conversation list.
- `lib/ui/screens/ai_chat/components/approval_card.dart`: approval UI for guarded actions.
- `lib/ui/screens/ai_chat/components/file_result_card.dart`: parsed file result UI.
- `lib/ui/screens/ai_chat/components/model_selector_button.dart`: grouped provider/model selector shared by the full chat and side panel headers.
- `lib/ui/screens/ai_chat/components/referenced_file_card.dart`: referenced file display.
- `lib/ui/screens/ai_chat/components/shimmer_thinking_text.dart`: thinking indicator.

## Localization

User-facing strings are defined in the custom localization files:

- `lib/config/languages/app_localizations.dart`
- `lib/config/languages/english_localizations.dart`
- `lib/config/languages/vietnamese_localizations.dart`

The BLoC receives localized thinking and approval strings from the UI layer so provider/tool execution state can be displayed without hardcoding one language in state logic.

## Extension Checklist

- Add new tools to `ToolExecutor._knownTools`, `execute`, `toolDefinitions`, and `AiAgentBloc._toolNames`.
- Add approval handling for any tool that creates, modifies, deletes, or executes outside the app.
- Keep tool outputs bounded before returning them to the model.
- Update this document when adding provider types, tools, persistence keys, or new AI entry points.
- Add or update localized strings for any visible UI text.

_Last reviewed: 2026-05-03_
