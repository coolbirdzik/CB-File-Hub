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
- `read_file`: read supported text files up to safe limits.
- `write_file`: create, overwrite, or append text files.
- `delete_file`: move one or more files to the recycle bin.
- `get_file_info`: return metadata for a file or directory.
- `run_command`: execute a shell command with timeout and blocking rules.
- `search_by_tag`: find files with a tag globally or within a path.
- `get_file_tags`: list tags attached to one file.
- `list_all_tags`: list all known tags.
- `search_content`: grep-like recursive search inside text files.

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
